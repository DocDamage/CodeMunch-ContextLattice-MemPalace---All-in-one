#requires -Version 5.1
<#
.SYNOPSIS
    Educational content extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Extracts structured metadata from educational ML content including:
    - Tutorial structures and learning paths
    - Exercise patterns and problem sets
    - Concept hierarchies and topic taxonomies
    - Code examples from notebooks and markdown
    
    This extractor implements the educational content parsing requirements
    for the ML Educational Reference Pack.

.NOTES
    File Name      : EducationalContentExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Tutorial structure patterns
$script:TutorialPatterns = @{
    # Markdown headers for structure
    H1 = '^\s*#\s+(?<title>.+)$'
    H2 = '^\s*##\s+(?<title>.+)$'
    H3 = '^\s*###\s+(?<title>.+)$'
    H4 = '^\s*####\s+(?<title>.+)$'
    
    # Exercise patterns
    ExerciseHeader = '^\s*#*\s*(?:Exercise|Problem|Assignment|Lab|Homework)\s*(?:\d+)?[:\s]*(?<title>.*)$'
    ExerciseNumbered = '^\s*(?:Exercise|Problem)\s+(?<number>\d+)[:\.\s]+(?<title>.*)$'
    
    # Concept markers
    Definition = '^\s*#*\s*(?:Definition|Concept|Term)[:\s]*(?<term>.+)$'
    ConceptBlock = '^\s*#*\s*(?:Key Concept|Important|Takeaway)[:\s]*(?<content>.+)$'
    
    # Code block markers
    CodeBlockStart = '^\s*```(?<language>\w+)?'
    CodeBlockEnd = '^\s*```\s*$'
    InlineCode = '`(?<code>[^`]+)`'
    
    # Learning objectives
    LearningObjective = '^\s*#*\s*(?:Learning Objective|Goal|Outcome|By the end)[:\s]*(?<objective>.+)$'
    
    # Prerequisites
    Prerequisite = '^\s*#*\s*(?:Prerequisite|Before you begin|Requirements?)[:\s]*(?<prereq>.+)$'
}

# Jupyter notebook cell types
$script:NotebookPatterns = @{
    MarkdownCell = '"cell_type":\s*"markdown"'
    CodeCell = '"cell_type":\s*"code"'
    OutputCell = '"outputs":'
    CellSource = '"source":\s*\[(?<content>[^\]]*)\]'
    CellMetadata = '"metadata":\s*\{'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Normalizes markdown content by cleaning up whitespace and formatting.
.DESCRIPTION
    Internal helper to clean up extracted markdown content.
.PARAMETER Content
    The content to normalize.
.OUTPUTS
    System.String. Normalized content string.
#>
function ConvertTo-NormalizedContent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    # Remove trailing whitespace
    $lines = $Content -split "`r?`n"
    $normalized = $lines | ForEach-Object { $_.TrimEnd() }
    return ($normalized -join "`n").Trim()
}

<#
.SYNOPSIS
    Parses a markdown header line to extract level and title.
.DESCRIPTION
    Internal helper to parse header lines.
.PARAMETER Line
    The line to parse.
.OUTPUTS
    System.Collections.Hashtable. Header info or $null.
#>
function ConvertFrom-HeaderLine {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )
    
    for ($level = 1; $level -le 6; $level++) {
        $pattern = "^\s*#{$level}\s+(?<title>.+)$"
        if ($Line -match $pattern) {
            return @{
                level = $level
                title = $matches['title'].Trim()
            }
        }
    }
    return $null
}

<#
.SYNOPSIS
    Creates a structured element object for educational content.
.DESCRIPTION
    Factory function to create standardized educational content elements.
.PARAMETER ElementType
    The type of element.
.PARAMETER Title
    The title or name.
.PARAMETER Content
    The content text.
.PARAMETER LineNumber
    The line number where found.
.OUTPUTS
    System.Collections.Hashtable. Structured element object.
#>
function New-EducationalElement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('section', 'exercise', 'concept', 'code_example', 'learning_objective', 'prerequisite')]
        [string]$ElementType,
        
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter()]
        [string]$Content = '',
        
        [Parameter()]
        [int]$LineNumber = 0,
        
        [Parameter()]
        [int]$Level = 0,
        
        [Parameter()]
        [string]$Language = '',
        
        [Parameter()]
        [string]$SourceFile = ''
    )
    
    return @{
        elementType = $ElementType
        title = $Title
        content = $Content
        lineNumber = $LineNumber
        level = $Level
        language = $Language
        sourceFile = $SourceFile
        children = @()
    }
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts tutorial structure from educational content files.

.DESCRIPTION
    Parses tutorial files (markdown, notebooks) and extracts the hierarchical
    structure including sections, subsections, and learning progression.

.PARAMETER Path
    Path to the tutorial file to parse.

.PARAMETER Content
    Tutorial content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Tutorial structure with sections hierarchy.

.EXAMPLE
    $structure = Get-TutorialStructure -Path "tutorial.md"

.EXAMPLE
    $content = Get-Content -Raw "tutorial.md"
    $structure = Get-TutorialStructure -Content $content
#>
function Get-TutorialStructure {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $filePath = ''
        $rawContent = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[Get-TutorialStructure] Loading file: $Path"
            
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
        
        Write-Verbose "[Get-TutorialStructure] Parsing tutorial structure"
        
        $lines = $rawContent -split "`r?`n"
        $sections = @()
        $currentSection = $null
        $sectionStack = @()
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $header = ConvertFrom-HeaderLine -Line $line
            
            if ($header) {
                $section = New-EducationalElement `
                    -ElementType 'section' `
                    -Title $header.title `
                    -LineNumber $lineNumber `
                    -Level $header.level `
                    -SourceFile $filePath
                
                # Manage hierarchy
                while ($sectionStack.Count -gt 0 -and $sectionStack[-1].level -ge $header.level) {
                    $sectionStack = $sectionStack[0..($sectionStack.Count - 2)]
                }
                
                if ($sectionStack.Count -eq 0) {
                    $sections += $section
                }
                else {
                    $sectionStack[-1].children += $section
                }
                
                $sectionStack += $section
            }
        }
        
        $result = @{
            fileType = 'tutorial'
            filePath = $filePath
            sections = $sections
            sectionCount = $sections.Count
            maxDepth = ($sections | ForEach-Object { Get-SectionDepth $_ } | Measure-Object -Maximum).Maximum
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        Write-Verbose "[Get-TutorialStructure] Found $($sections.Count) top-level sections"
        return $result
    }
    catch {
        Write-Error "[Get-TutorialStructure] Failed to parse tutorial: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Helper function to calculate section depth recursively.
#>
function Get-SectionDepth {
    param([hashtable]$Section)
    
    if ($Section.children.Count -eq 0) {
        return 1
    }
    
    $maxChildDepth = 1
    foreach ($child in $Section.children) {
        $childDepth = Get-SectionDepth -Section $child
        if ($childDepth -gt $maxChildDepth) {
            $maxChildDepth = $childDepth
        }
    }
    return 1 + $maxChildDepth
}

<#
.SYNOPSIS
    Extracts exercise patterns from educational content.

.DESCRIPTION
    Identifies and extracts exercises, problems, assignments, and lab materials
    from educational content files.

.PARAMETER Path
    Path to the content file.

.PARAMETER Content
    Content string (alternative to Path).

.OUTPUTS
    System.Array. Array of exercise pattern objects.

.EXAMPLE
    $exercises = Get-ExercisePatterns -Path "assignment.md"
#>
function Get-ExercisePatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $rawContent = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $rawContent = $Content
        }
        
        $exercises = @()
        $lines = $rawContent -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Check for exercise headers
            if ($line -match $script:TutorialPatterns.ExerciseHeader -or
                $line -match $script:TutorialPatterns.ExerciseNumbered) {
                
                $exerciseType = if ($line -match 'Lab|Assignment|Homework') { 'assignment' } else { 'exercise' }
                $number = if ($matches['number']) { $matches['number'] } else { '' }
                $title = if ($matches['title']) { $matches['title'].Trim() } else { 'Untitled' }
                
                $exercise = New-EducationalElement `
                    -ElementType 'exercise' `
                    -Title $title `
                    -LineNumber $lineNumber
                
                $exercise.number = $number
                $exercise.exerciseType = $exerciseType
                
                $exercises += $exercise
                Write-Verbose "[Get-ExercisePatterns] Found $exerciseType`: $title"
            }
        }
        
        return ,$exercises
    }
    catch {
        Write-Error "[Get-ExercisePatterns] Failed to extract exercises: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts concept hierarchies from educational content.

.DESCRIPTION
    Identifies and extracts concept definitions, key terms, and topic taxonomies
    from educational materials.

.PARAMETER Path
    Path to the content file.

.PARAMETER Content
    Content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Concept hierarchy structure.

.EXAMPLE
    $hierarchy = Get-ConceptHierarchy -Path "course.md"
#>
function Get-ConceptHierarchy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        $rawContent = ''
        $filePath = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $filePath = $Path
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return $null
            }
            $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $rawContent = $Content
        }
        
        $concepts = @()
        $lines = $rawContent -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Check for definitions
            if ($line -match $script:TutorialPatterns.Definition) {
                $concept = New-EducationalElement `
                    -ElementType 'concept' `
                    -Title $matches['term'].Trim() `
                    -LineNumber $lineNumber
                
                $concept.conceptType = 'definition'
                $concepts += $concept
            }
            # Check for concept blocks
            elseif ($line -match $script:TutorialPatterns.ConceptBlock) {
                $concept = New-EducationalElement `
                    -ElementType 'concept' `
                    -Title $matches['content'].Trim() `
                    -LineNumber $lineNumber
                
                $concept.conceptType = 'key_concept'
                $concepts += $concept
            }
        }
        
        $result = @{
            filePath = $filePath
            concepts = $concepts
            conceptCount = $concepts.Count
            definitions = ($concepts | Where-Object { $_.conceptType -eq 'definition' }).Count
            keyConcepts = ($concepts | Where-Object { $_.conceptType -eq 'key_concept' }).Count
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        return $result
    }
    catch {
        Write-Error "[Get-ConceptHierarchy] Failed to extract concepts: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts code examples from educational content.

.DESCRIPTION
    Identifies and extracts code blocks and inline code from tutorials,
    notebooks, and markdown files.

.PARAMETER Path
    Path to the content file.

.PARAMETER Content
    Content string (alternative to Path).

.PARAMETER Language
    Optional filter for specific programming language.

.OUTPUTS
    System.Array. Array of code example objects.

.EXAMPLE
    $codeExamples = Get-CodeExamples -Path "tutorial.md"

.EXAMPLE
    $pythonExamples = Get-CodeExamples -Path "tutorial.md" -Language "python"
#>
function Get-CodeExamples {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [string]$Language = ''
    )
    
    try {
        $rawContent = ''
        $filePath = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $filePath = $Path
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "File not found: $Path"
                return @()
            }
            $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $rawContent = $Content
        }
        
        # Handle Jupyter notebooks
        if ($filePath -match '\.ipynb$' -or $rawContent -match '"cell_type"') {
            return Get-NotebookCodeExamples -Content $rawContent -FilePath $filePath -LanguageFilter $Language
        }
        
        # Handle Markdown files
        $examples = @()
        $lines = $rawContent -split "`r?`n"
        $lineNumber = 0
        $inCodeBlock = $false
        $currentCode = @()
        $currentLanguage = ''
        $codeStartLine = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            if ($line -match $script:TutorialPatterns.CodeBlockStart) {
                $inCodeBlock = $true
                $currentLanguage = $matches['language']
                $codeStartLine = $lineNumber
                $currentCode = @()
            }
            elseif ($line -match $script:TutorialPatterns.CodeBlockEnd -and $inCodeBlock) {
                $inCodeBlock = $false
                
                if ($currentCode.Count -gt 0) {
                    $shouldInclude = [string]::IsNullOrEmpty($Language) -or 
                                     ($currentLanguage -eq $Language)
                    
                    if ($shouldInclude) {
                        $example = New-EducationalElement `
                            -ElementType 'code_example' `
                            -Title "Code block at line $codeStartLine" `
                            -Content ($currentCode -join "`n") `
                            -LineNumber $codeStartLine `
                            -Language $currentLanguage `
                            -SourceFile $filePath
                        
                        $examples += $example
                    }
                }
                
                $currentCode = @()
            }
            elseif ($inCodeBlock) {
                $currentCode += $line
            }
        }
        
        return ,$examples
    }
    catch {
        Write-Error "[Get-CodeExamples] Failed to extract code examples: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Helper function to extract code from Jupyter notebooks.
#>
function Get-NotebookCodeExamples {
    param(
        [string]$Content,
        [string]$FilePath,
        [string]$LanguageFilter
    )
    
    $examples = @()
    
    try {
        $notebook = $Content | ConvertFrom-Json
        $cellIndex = 0
        
        foreach ($cell in $notebook.cells) {
            $cellIndex++
            
            if ($cell.cell_type -eq 'code') {
                $source = $cell.source -join ""
                
                if (-not [string]::IsNullOrWhiteSpace($source)) {
                    $shouldInclude = [string]::IsNullOrEmpty($LanguageFilter) -or
                                     ($notebook.metadata.kernelspec.language -eq $LanguageFilter)
                    
                    if ($shouldInclude) {
                        $example = New-EducationalElement `
                            -ElementType 'code_example' `
                            -Title "Notebook cell $cellIndex" `
                            -Content $source `
                            -LineNumber $cellIndex `
                            -Language $notebook.metadata.kernelspec.language `
                            -SourceFile $FilePath
                        
                        $examples += $example
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to parse notebook: $_"
    }
    
    return $examples
}

# Export public functions
Export-ModuleMember -Function Get-TutorialStructure, Get-ExercisePatterns, Get-ConceptHierarchy, Get-CodeExamples
