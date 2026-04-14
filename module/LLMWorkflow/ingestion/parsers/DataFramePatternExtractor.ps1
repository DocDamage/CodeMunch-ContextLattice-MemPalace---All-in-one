#requires -Version 5.1
<#
.SYNOPSIS
    DataFrame Pattern Extractor for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Extracts pandas DataFrame operations, transformation patterns, and visualization
    code from Python source files. Identifies common patterns such as:
    - DataFrame creation and manipulation operations
    - Data transformation patterns (cleaning, aggregation, reshaping)
    - Visualization code using matplotlib, seaborn, plotly
    - Data lineage tracking between operations
    - Data quality validation patterns
    - Mito-specific spreadsheet patterns
    
    This parser implements Section 25.15.2 of the canonical architecture
    for the Notebook/Data Workflow pack's structured extraction pipeline.

.NOTES
    File Name      : DataFramePatternExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Library Support: pandas, numpy, matplotlib, seaborn, plotly, mito
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

# Pandas DataFrame operation patterns
$script:DataFramePatterns = @{
    # DataFrame creation
    ReadCsv = '(?:pd\.read_csv|pandas\.read_csv)\s*\(\s*(?<path>[^,)]+)'
    ReadExcel = '(?:pd\.read_excel|pandas\.read_excel)\s*\(\s*(?<path>[^,)]+)'
    ReadSql = '(?:pd\.read_sql|pandas\.read_sql)\s*\(\s*(?<query>[^,]+)'
    DataFrame = '(?:pd\.DataFrame|pandas\.DataFrame)\s*\((?<data>[^)]*)\)'
    
    # Common methods
    Head = '\.(?<var>\w+)\.head\s*\((?<n>\d*)\)'
    Tail = '\.(?<var>\w+)\.tail\s*\((?<n>\d*)\)'
    Info = '\.(?<var>\w+)\.info\s*\(\s*\)'
    Describe = '\.(?<var>\w+)\.describe\s*\(\s*\)'
    Shape = '\.(?<var>\w+)\.shape'
    Columns = '\.(?<var>\w+)\.columns'
    Index = '\.(?<var>\w+)\.index'
    Dtypes = '\.(?<var>\w+)\.dtypes'
    
    # Selection and filtering
    Loc = '\.(?<var>\w+)\.loc\[(?<selector>[^\]]+)\]'
    Iloc = '\.(?<var>\w+)\.iloc\[(?<selector>[^\]]+)\]'
    Query = '\.(?<var>\w+)\.query\s*\(\s*["''](?<expr>[^"'']+)["'']\s*\)'
    BooleanIndex = '(?<var>\w+)\[(?<condition>[^\]]+)\]'
    
    # Column operations
    Drop = '\.(?<var>\w+)\.drop\s*\(\s*(?<cols>[^)]+)\s*\)'
    DropColumns = '\.(?<var>\w+)\.drop\s*\(\s*columns\s*=\s*(?<cols>[^)]+)\)'
    Rename = '\.(?<var>\w+)\.rename\s*\(\s*columns\s*=\s*(?<mapper>\{[^}]+\})\s*\)'
    Assign = '\.(?<var>\w+)\.assign\s*\((?<assignments>[^)]+)\)'
    
    # Missing data
    DropNa = '\.(?<var>\w+)\.dropna\s*\(\s*\)'
    FillNa = '\.(?<var>\w+)\.fillna\s*\(\s*(?<value>[^)]+)\s*\)'
    IsNull = '\.(?<var>\w+)\.isnull\s*\(\s*\)'
    IsNa = '\.(?<var>\w+)\.isna\s*\(\s*\)'
    
    # Grouping and aggregation
    GroupBy = '\.(?<var>\w+)\.groupby\s*\(\s*(?<cols>[^)]+)\s*\)'
    Pivot = '\.(?<var>\w+)\.pivot\s*\(\s*(?<args>[^)]+)\s*\)'
    PivotTable = '\.(?<var>\w+)\.pivot_table\s*\(\s*(?<args>[^)]+)\s*\)'
    Melt = '\.(?<var>\w+)\.melt\s*\(\s*(?<args>[^)]+)\s*\)'
    Stack = '\.(?<var>\w+)\.stack\s*\(\s*\)'
    Unstack = '\.(?<var>\w+)\.unstack\s*\(\s*\)'
    
    # Join/merge operations
    Merge = '(?<left>\w+)\.merge\s*\(\s*(?<right>\w+)\s*,\s*(?<args>[^)]+)\s*\)'
    Join = '(?<left>\w+)\.join\s*\(\s*(?<right>\w+)\s*\)'
    Concat = '(?:pd\.concat|pandas\.concat)\s*\(\s*(?<objs>\[[^\]]+\])\s*\)'
    
    # Sorting
    SortValues = '\.(?<var>\w+)\.sort_values\s*\(\s*by\s*=\s*(?<cols>[^)]+)\s*\)'
    SortIndex = '\.(?<var>\w+)\.sort_index\s*\(\s*\)'
    
    # Export
    ToCsv = '\.(?<var>\w+)\.to_csv\s*\(\s*(?<path>[^)]+)\s*\)'
    ToExcel = '\.(?<var>\w+)\.to_excel\s*\(\s*(?<path>[^)]+)\s*\)'
    
    # Apply and transform
    Apply = '\.(?<var>\w+)\.apply\s*\(\s*(?<func>[^)]+)\s*\)'
    Map = '\.(?<var>\w+)\.map\s*\(\s*(?<arg>[^)]+)\s*\)'
    ApplyMap = '\.(?<var>\w+)\.applymap\s*\(\s*(?<func>[^)]+)\s*\)'
    Transform = '\.(?<var>\w+)\.transform\s*\(\s*(?<func>[^)]+)\s*\)'
}

# Visualization library patterns
$script:VisualizationPatterns = @{
    # Matplotlib pyplot
    PltFigure = '(?:plt|matplotlib\.pyplot)\.figure\s*\(\s*(?<args>[^)]*)\s*\)'
    PltPlot = '(?:plt|matplotlib\.pyplot)\.plot\s*\(\s*(?<args>[^)]+)\s*\)'
    PltScatter = '(?:plt|matplotlib\.pyplot)\.scatter\s*\(\s*(?<args>[^)]+)\s*\)'
    PltBar = '(?:plt|matplotlib\.pyplot)\.bar\s*\(\s*(?<args>[^)]+)\s*\)'
    PltHist = '(?:plt|matplotlib\.pyplot)\.hist\s*\(\s*(?<args>[^)]+)\s*\)'
    PltBoxplot = '(?:plt|matplotlib\.pyplot)\.boxplot\s*\(\s*(?<args>[^)]+)\s*\)'
    PltPie = '(?:plt|matplotlib\.pyplot)\.pie\s*\(\s*(?<args>[^)]+)\s*\)'
    PltImshow = '(?:plt|matplotlib\.pyplot)\.imshow\s*\(\s*(?<args>[^)]+)\s*\)'
    PltXlabel = '(?:plt|matplotlib\.pyplot)\.xlabel\s*\(\s*["''](?<label>[^"'']*)["'']\s*\)'
    PltYlabel = '(?:plt|matplotlib\.pyplot)\.ylabel\s*\(\s*["''](?<label>[^"'']*)["'']\s*\)'
    PltTitle = '(?:plt|matplotlib\.pyplot)\.title\s*\(\s*["''](?<title>[^"'']*)["'']\s*\)'
    PltLegend = '(?:plt|matplotlib\.pyplot)\.legend\s*\(\s*\)'
    PltShow = '(?:plt|matplotlib\.pyplot)\.show\s*\(\s*\)'
    PltSavefig = '(?:plt|matplotlib\.pyplot)\.savefig\s*\(\s*(?<path>[^)]+)\s*\)'
    
    # DataFrame plot method
    DfPlot = '\.(?<var>\w+)\.plot\.(?<kind>\w+)\s*\(\s*(?<args>[^)]+)\s*\)'
    DfPlotSimple = '\.(?<var>\w+)\.plot\s*\(\s*(?<args>[^)]*)\s*\)'
    
    # Seaborn
    SnsDistplot = '(?:sns|seaborn)\.\w*plot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsScatter = '(?:sns|seaborn)\.scatterplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsLine = '(?:sns|seaborn)\.lineplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsBar = '(?:sns|seaborn)\.barplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsBox = '(?:sns|seaborn)\.boxplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsHeatmap = '(?:sns|seaborn)\.heatmap\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsPairplot = '(?:sns|seaborn)\.pairplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsCatplot = '(?:sns|seaborn)\.catplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsRelplot = '(?:sns|seaborn)\.relplot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsDisplot = '(?:sns|seaborn)\.displot\s*\(\s*(?<args>[^)]+)\s*\)'
    SnsHistplot = '(?:sns|seaborn)\.histplot\s*\(\s*(?<args>[^)]+)\s*\)'
    
    # Plotly
    PxScatter = '(?:px|plotly\.express)\.scatter\s*\(\s*(?<args>[^)]+)\s*\)'
    PxLine = '(?:px|plotly\.express)\.line\s*\(\s*(?<args>[^)]+)\s*\)'
    PxBar = '(?:px|plotly\.express)\.bar\s*\(\s*(?<args>[^)]+)\s*\)'
    PxHistogram = '(?:px|plotly\.express)\.histogram\s*\(\s*(?<args>[^)]+)\s*\)'
    PxBox = '(?:px|plotly\.express)\.box\s*\(\s*(?<args>[^)]+)\s*\)'
    PxViolin = '(?:px|plotly\.express)\.violin\s*\(\s*(?<args>[^)]+)\s*\)'
    PxPie = '(?:px|plotly\.express)\.pie\s*\(\s*(?<args>[^)]+)\s*\)'
    PxHeatmap = '(?:px|plotly\.express)\.\w*heatmap\s*\(\s*(?<args>[^)]+)\s*\)'
    PxScatter3d = '(?:px|plotly\.express)\.scatter_3d\s*\(\s*(?<args>[^)]+)\s*\)'
}

# Data transformation pattern categories
$script:TransformCategories = @{
    'read' = @('ReadCsv', 'ReadExcel', 'ReadSql', 'DataFrame')
    'write' = @('ToCsv', 'ToExcel')
    'inspect' = @('Head', 'Tail', 'Info', 'Describe', 'Shape', 'Columns', 'Index', 'Dtypes')
    'select' = @('Loc', 'Iloc', 'Query', 'BooleanIndex')
    'filter' = @('BooleanIndex', 'Query')
    'reshape' = @('Pivot', 'PivotTable', 'Melt', 'Stack', 'Unstack')
    'aggregate' = @('GroupBy')
    'join' = @('Merge', 'Join', 'Concat')
    'clean' = @('DropNa', 'FillNa', 'IsNull', 'IsNa', 'Drop', 'DropColumns', 'Rename')
    'sort' = @('SortValues', 'SortIndex')
    'transform' = @('Apply', 'Map', 'ApplyMap', 'Transform', 'Assign')
}

# Data quality patterns
$script:DataQualityPatterns = @{
    nullCheck = '(?:isnull|isna|notnull|notna)\s*\(\s*\)'
    duplicateCheck = '\.duplicated\s*\(\s*\)'
    dropDuplicates = '\.drop_duplicates\s*\(\s*\)'
    astype = '\.astype\s*\(\s*(?<dtype>[^)]+)\s*\)'
    toNumeric = '(?:pd\.to_numeric|pandas\.to_numeric)\s*\('
    toDatetime = '(?:pd\.to_datetime|pandas\.to_datetime)\s*\('
    strReplace = '\.str\.replace\s*\('
    strStrip = '\.str\.\w*strip\s*\(\s*\)'
    strLower = '\.str\.lower\s*\(\s*\)'
    strUpper = '\.str\.upper\s*\(\s*\)'
    clip = '\.clip\s*\('
    between = '\.between\s*\('
}

# Mito-specific patterns
$script:MitoPatterns = @{
    importSheet = 'mitosheet\.sheet\s*\('
    runTransform = 'mitosheet\.(?<transform>\w+)\s*\('
    generatedCode = '#\s*MITO\s*CODE\s*START|#\s*MITO\s*GENERATED\s*CODE'
    undo = 'mitosheet\.undo\s*\(\s*\)'
    redo = 'mitosheet\.redo\s*\(\s*\)'
    clear = 'mitosheet\.clear\s*\(\s*\)'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts variable assignments from Python code.
.DESCRIPTION
    Identifies variable names and their assigned values/expressions.
.PARAMETER Content
    The Python code content.
.OUTPUTS
    System.Array. Array of variable assignment objects.
#>
function Get-VariableAssignments {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $assignments = @()
    $lines = $Content -split "`r?`n"
    $lineNumber = 0
    
    foreach ($line in $lines) {
        $lineNumber++
        
        # Match variable = expression patterns (but not == comparisons)
        if ($line -match '^\s*(?<var>[a-zA-Z_]\w*)\s*=\s*(?<expr>.+)$' -and 
            $line -notmatch '^\s*#') {
            $assignments += @{
                variable = $matches['var']
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                isDataFrame = $matches['expr'] -match 'pd\.DataFrame|read_csv|read_excel|read_sql'
            }
        }
    }
    
    return $assignments
}

<#
.SYNOPSIS
    Categorizes a DataFrame operation.
.DESCRIPTION
    Determines the category of operation based on pattern name.
.PARAMETER PatternName
    The name of the matched pattern.
.OUTPUTS
    System.String. The category name.
#>
function Get-OperationCategory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PatternName
    )
    
    foreach ($category in $script:TransformCategories.Keys) {
        if ($script:TransformCategories[$category] -contains $PatternName) {
            return $category
        }
    }
    
    return 'other'
}

<#
.SYNOPSIS
    Extracts imports from Python code.
.DESCRIPTION
    Identifies imported libraries for dependency tracking.
.PARAMETER Content
    The Python code content.
.OUTPUTS
    System.Array. Array of import objects.
#>
function Get-PythonImports {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    $imports = @()
    
    # Standard imports
    $importMatches = [regex]::Matches($Content, '(?m)^import\s+(?<mod>\w+(?:\s*,\s*\w+)*)')
    foreach ($match in $importMatches) {
        $modules = $match.Groups['mod'].Value -split '\s*,\s*'
        foreach ($mod in $modules) {
            $imports += @{
                type = 'import'
                module = $mod.Trim()
                alias = $null
            }
        }
    }
    
    # From imports
    $fromMatches = [regex]::Matches($Content, '(?m)^from\s+(?<mod>[\w.]+)\s+import\s+(?<names>[^\n]+)')
    foreach ($match in $fromMatches) {
        $imports += @{
            type = 'from'
            module = $match.Groups['mod'].Value
            names = $match.Groups['names'].Value.Trim()
        }
    }
    
    # Import as
    $asMatches = [regex]::Matches($Content, '(?m)^import\s+(?<mod>\w+)\s+as\s+(?<alias>\w+)')
    foreach ($match in $asMatches) {
        $imports += @{
            type = 'import-as'
            module = $match.Groups['mod'].Value
            alias = $match.Groups['alias'].Value
        }
    }
    
    return $imports
}

<#
.SYNOPSIS
    Builds a data lineage map from operations.
.DESCRIPTION
    Tracks how DataFrames are created, transformed, and passed between operations.
.PARAMETER Operations
    Array of extracted operations.
.PARAMETER Assignments
    Array of variable assignments.
.OUTPUTS
    System.Collections.Hashtable. Lineage map with dependencies.
#>
function Build-DataLineage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Operations,
        
        [Parameter(Mandatory = $true)]
        [array]$Assignments
    )
    
    $lineage = @{
        sources = @()
        transforms = @()
        sinks = @()
        dependencies = @{}
    }
    
    # Track source DataFrames
    foreach ($op in $Operations | Where-Object { $_.category -eq 'read' }) {
        $lineage.sources += @{
            variable = $op.variable
            operation = $op.operation
            lineNumber = $op.lineNumber
        }
    }
    
    # Track transformations
    foreach ($op in $Operations | Where-Object { $_.category -in @('select', 'filter', 'reshape', 'aggregate', 'clean', 'sort', 'transform') }) {
        $lineage.transforms += @{
            variable = $op.variable
            operation = $op.operation
            category = $op.category
            lineNumber = $op.lineNumber
        }
    }
    
    # Track sinks (exports/outputs)
    foreach ($op in $Operations | Where-Object { $_.category -eq 'write' }) {
        $lineage.sinks += @{
            variable = $op.variable
            operation = $op.operation
            lineNumber = $op.lineNumber
        }
    }
    
    # Build dependency graph
    $dfVars = $Operations | ForEach-Object { $_.variable } | Select-Object -Unique
    foreach ($var in $dfVars) {
        $varOps = $Operations | Where-Object { $_.variable -eq $var } | Sort-Object lineNumber
        if ($varOps.Count -gt 0) {
            $lineage.dependencies[$var] = @{
                firstOperation = $varOps[0].operation
                lastOperation = $varOps[-1].operation
                operationCount = $varOps.Count
                categories = ($varOps | ForEach-Object { $_.category } | Select-Object -Unique)
            }
        }
    }
    
    return $lineage
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts DataFrame operations from Python source code.

.DESCRIPTION
    Parses Python code and identifies all pandas DataFrame operations including
    reads, writes, transformations, and manipulations.

.PARAMETER Path
    Path to the Python file to parse.

.PARAMETER Content
    Python code string (alternative to Path).

.PARAMETER IncludeLineNumbers
    If specified, includes line number information for each operation.

.OUTPUTS
    System.Array. Array of operation objects with details.

.EXAMPLE
    $ops = Get-DataFrameOperations -Path "analysis.py"

.EXAMPLE
    $code = Get-Content -Raw "script.py"
    $ops = Get-DataFrameOperations -Content $code -IncludeLineNumbers
#>
function Get-DataFrameOperations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeLineNumbers
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[Get-DataFrameOperations] Loading file: $Path"
            
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
                return @()
            }
            
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
        }
        
        $operations = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            foreach ($patternName in $script:DataFramePatterns.Keys) {
                $pattern = $script:DataFramePatterns[$patternName]
                $matches = [regex]::Matches($line, $pattern)
                
                foreach ($match in $matches) {
                    $op = @{
                        operation = $patternName
                        category = Get-OperationCategory -PatternName $patternName
                        matchedText = $match.Value
                    }
                    
                    if ($IncludeLineNumbers) {
                        $op.lineNumber = $lineNumber
                    }
                    
                    # Extract variable name if available
                    if ($match.Groups['var'].Success) {
                        $op.variable = $match.Groups['var'].Value
                    }
                    
                    # Extract additional details based on operation type
                    switch ($patternName) {
                        { $_ -in @('ReadCsv', 'ReadExcel') } {
                            if ($match.Groups['path'].Success) {
                                $op.sourcePath = $match.Groups['path'].Value
                            }
                        }
                        { $_ -in @('ToCsv', 'ToExcel') } {
                            if ($match.Groups['path'].Success) {
                                $op.outputPath = $match.Groups['path'].Value
                            }
                        }
                        'GroupBy' {
                            if ($match.Groups['cols'].Success) {
                                $op.groupByColumns = $match.Groups['cols'].Value
                            }
                        }
                        'Merge' {
                            if ($match.Groups['right'].Success) {
                                $op.mergeWith = $match.Groups['right'].Value
                            }
                        }
                    }
                    
                    $operations += $op
                }
            }
        }
        
        Write-Verbose "[Get-DataFrameOperations] Found $($operations.Count) operations"
        return $operations
    }
    catch {
        Write-Error "[Get-DataFrameOperations] Failed to extract operations: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Identifies data transformation patterns in code.

.DESCRIPTION
    Analyzes Python code to identify common data transformation patterns
    such as cleaning, aggregation, reshaping, and feature engineering.

.PARAMETER Path
    Path to the Python file to analyze.

.PARAMETER Content
    Python code string (alternative to Path).

.PARAMETER IncludeLineNumbers
    If specified, includes line number information.

.OUTPUTS
    System.Array. Array of transformation pattern objects.

.EXAMPLE
    $patterns = Get-DataTransformPatterns -Path "transforms.py"

.EXAMPLE
    Get-DataTransformPatterns -Content $code -IncludeLineNumbers
#>
function Get-DataTransformPatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeLineNumbers
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
                return @()
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
        }
        
        $patterns = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        # Define transformation patterns with descriptions
        $transformSignatures = @{
            'missing-value-imputation' = @(
                @{ pattern = '\.fillna\s*\('; description = 'Fill missing values' }
                @{ pattern = '\.interpolate\s*\('; description = 'Interpolate missing values' }
                @{ pattern = '\.dropna\s*\('; description = 'Drop rows with missing values' }
            )
            'duplication-handling' = @(
                @{ pattern = '\.drop_duplicates\s*\('; description = 'Remove duplicate rows' }
                @{ pattern = '\.duplicated\s*\('; description = 'Identify duplicates' }
            )
            'type-conversion' = @(
                @{ pattern = '\.astype\s*\('; description = 'Convert column types' }
                @{ pattern = 'pd\.to_numeric\s*\('; description = 'Convert to numeric' }
                @{ pattern = 'pd\.to_datetime\s*\('; description = 'Convert to datetime' }
            )
            'aggregation' = @(
                @{ pattern = '\.groupby\s*\([^)]+\)\.\w+\s*\(\s*\)'; description = 'Group by and aggregate' }
                @{ pattern = '\.pivot_table\s*\('; description = 'Create pivot table' }
                @{ pattern = '\.agg\s*\('; description = 'Custom aggregation' }
            )
            'reshaping' = @(
                @{ pattern = '\.melt\s*\('; description = 'Unpivot data (wide to long)' }
                @{ pattern = '\.pivot\s*\('; description = 'Pivot data (long to wide)' }
                @{ pattern = '\.stack\s*\(\s*\)'; description = 'Stack columns' }
                @{ pattern = '\.unstack\s*\(\s*\)'; description = 'Unstack index' }
            )
            'feature-engineering' = @(
                @{ pattern = '\.assign\s*\('; description = 'Create new columns' }
                @{ pattern = '\.apply\s*\('; description = 'Apply function' }
                @{ pattern = '\.map\s*\('; description = 'Map values' }
            )
            'filtering' = @(
                @{ pattern = '\.query\s*\('; description = 'Query with expression' }
                @{ pattern = '\[\s*\w+\s*[<>=!]+'; description = 'Boolean indexing' }
                @{ pattern = '\.between\s*\('; description = 'Range filtering' }
            )
            'joining' = @(
                @{ pattern = '\.merge\s*\('; description = 'Merge DataFrames' }
                @{ pattern = '\.join\s*\('; description = 'Join DataFrames' }
                @{ pattern = 'pd\.concat\s*\('; description = 'Concatenate DataFrames' }
            )
            'sorting' = @(
                @{ pattern = '\.sort_values\s*\('; description = 'Sort by values' }
                @{ pattern = '\.sort_index\s*\(\s*\)'; description = 'Sort by index' }
            )
            'text-processing' = @(
                @{ pattern = '\.str\.replace\s*\('; description = 'String replacement' }
                @{ pattern = '\.str\.\w*strip\s*\('; description = 'Strip whitespace' }
                @{ pattern = '\.str\.lower\s*\(\s*\)'; description = 'Convert to lowercase' }
                @{ pattern = '\.str\.upper\s*\(\s*\)'; description = 'Convert to uppercase' }
                @{ pattern = '\.str\.contains\s*\('; description = 'String contains' }
                @{ pattern = '\.str\.split\s*\('; description = 'Split string' }
            )
        }
        
        foreach ($line in $lines) {
            $lineNumber++
            
            foreach ($category in $transformSignatures.Keys) {
                foreach ($sig in $transformSignatures[$category]) {
                    if ($line -match $sig.pattern) {
                        $pattern = @{
                            pattern = $category
                            description = $sig.description
                            matchedCode = $matches[0]
                        }
                        
                        if ($IncludeLineNumbers) {
                            $pattern.lineNumber = $lineNumber
                        }
                        
                        $patterns += $pattern
                    }
                }
            }
        }
        
        return $patterns
    }
    catch {
        Write-Error "[Get-DataTransformPatterns] Failed to extract patterns: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts visualization code from Python source.

.DESCRIPTION
    Identifies and extracts visualization code using matplotlib, seaborn,
    plotly, and other visualization libraries.

.PARAMETER Path
    Path to the Python file to parse.

.PARAMETER Content
    Python code string (alternative to Path).

.PARAMETER IncludeLineNumbers
    If specified, includes line number information.

.PARAMETER Library
    Filter by visualization library (matplotlib, seaborn, plotly, all).

.OUTPUTS
    System.Array. Array of visualization code objects.

.EXAMPLE
    $viz = Get-VisualizationCode -Path "plots.py"

.EXAMPLE
    Get-VisualizationCode -Content $code -Library 'seaborn'
#>
function Get-VisualizationCode {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeLineNumbers,
        
        [Parameter()]
        [ValidateSet('all', 'matplotlib', 'seaborn', 'plotly', 'df-plot')]
        [string]$Library = 'all'
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
                return @()
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
        }
        
        $visualizations = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        # Determine which pattern sets to use
        $patternSets = @{}
        if ($Library -in @('all', 'matplotlib')) {
            $patternSets['matplotlib'] = @('PltFigure', 'PltPlot', 'PltScatter', 'PltBar', 'PltHist', 'PltBoxplot', 'PltPie', 'PltImshow', 'PltXlabel', 'PltYlabel', 'PltTitle', 'PltLegend', 'PltShow', 'PltSavefig')
        }
        if ($Library -in @('all', 'df-plot')) {
            $patternSets['df-plot'] = @('DfPlot', 'DfPlotSimple')
        }
        if ($Library -in @('all', 'seaborn')) {
            $patternSets['seaborn'] = @('SnsDistplot', 'SnsScatter', 'SnsLine', 'SnsBar', 'SnsBox', 'SnsHeatmap', 'SnsPairplot', 'SnsCatplot', 'SnsRelplot', 'SnsDisplot', 'SnsHistplot')
        }
        if ($Library -in @('all', 'plotly')) {
            $patternSets['plotly'] = @('PxScatter', 'PxLine', 'PxBar', 'PxHistogram', 'PxBox', 'PxViolin', 'PxPie', 'PxHeatmap', 'PxScatter3d')
        }
        
        foreach ($line in $lines) {
            $lineNumber++
            
            foreach ($libName in $patternSets.Keys) {
                foreach ($patternName in $patternSets[$libName]) {
                    if ($script:VisualizationPatterns.ContainsKey($patternName)) {
                        $pattern = $script:VisualizationPatterns[$patternName]
                        $matches = [regex]::Matches($line, $pattern)
                        
                        foreach ($match in $matches) {
                            $viz = @{
                                library = $libName
                                plotType = $patternName
                                matchedCode = $match.Value
                            }
                            
                            if ($IncludeLineNumbers) {
                                $viz.lineNumber = $lineNumber
                            }
                            
                            # Extract additional details
                            if ($match.Groups['var'].Success) {
                                $viz.dataFrame = $match.Groups['var'].Value
                            }
                            if ($match.Groups['kind'].Success) {
                                $viz.plotKind = $match.Groups['kind'].Value
                            }
                            if ($match.Groups['title'].Success) {
                                $viz.title = $match.Groups['title'].Value
                            }
                            if ($match.Groups['xlabel'].Success) {
                                $viz.xlabel = $match.Groups['xlabel'].Value
                            }
                            if ($match.Groups['ylabel'].Success) {
                                $viz.ylabel = $match.Groups['ylabel'].Value
                            }
                            
                            $visualizations += $viz
                        }
                    }
                }
            }
        }
        
        return $visualizations
    }
    catch {
        Write-Error "[Get-VisualizationCode] Failed to extract visualizations: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Creates a data lineage map from code.

.DESCRIPTION
    Analyzes Python code to build a map of data dependencies, tracking
    how DataFrames flow through operations from source to sink.

.PARAMETER Path
    Path to the Python file to analyze.

.PARAMETER Content
    Python code string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Data lineage map with sources, transforms, sinks, and dependencies.

.EXAMPLE
    $lineage = New-DataLineageMap -Path "pipeline.py"

.EXAMPLE
    $code = Get-Content -Raw "analysis.py"
    New-DataLineageMap -Content $code
#>
function New-DataLineageMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                sources = @()
                transforms = @()
                sinks = @()
                dependencies = @{}
            }
        }
        
        # Extract operations and assignments
        $operations = Get-DataFrameOperations -Content $Content -IncludeLineNumbers
        $assignments = Get-VariableAssignments -Content $Content
        
        # Build lineage
        $lineage = Build-DataLineage -Operations $operations -Assignments $assignments
        $lineage.codeStats = @{
            totalLines = ($Content -split "`r?`n").Count
            operationCount = $operations.Count
            assignmentCount = $assignments.Count
            dataFrameVariables = ($assignments | Where-Object { $_.isDataFrame } | Select-Object -ExpandProperty variable -Unique)
        }
        
        $lineage.imports = Get-PythonImports -Content $Content
        
        return $lineage
    }
    catch {
        Write-Error "[New-DataLineageMap] Failed to create lineage map: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Validates data quality patterns in code.

.DESCRIPTION
    Analyzes Python code to identify data quality validation patterns
    and checks for common data quality issues.

.PARAMETER Path
    Path to the Python file to analyze.

.PARAMETER Content
    Python code string (alternative to Path).

.PARAMETER CheckLevel
    Level of validation: basic, standard, or comprehensive.

.OUTPUTS
    System.Collections.Hashtable. Validation results with found patterns and recommendations.

.EXAMPLE
    $quality = Test-DataQualityPattern -Path "analysis.py"

.EXAMPLE
    Test-DataQualityPattern -Content $code -CheckLevel 'comprehensive'
#>
function Test-DataQualityPattern {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('basic', 'standard', 'comprehensive')]
        [string]$CheckLevel = 'standard'
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $result = @{
            foundPatterns = @()
            missingPatterns = @()
            recommendations = @()
            score = 0
            maxScore = 0
        }
        
        # Define patterns to check
        $patternsToCheck = @{
            'null-check' = @{ pattern = $script:DataQualityPatterns.nullCheck; weight = 2; level = 'basic' }
            'duplicate-check' = @{ pattern = $script:DataQualityPatterns.duplicateCheck; weight = 2; level = 'basic' }
            'type-conversion' = @{ pattern = $script:DataQualityPatterns.astype; weight = 1; level = 'basic' }
            'numeric-conversion' = @{ pattern = $script:DataQualityPatterns.toNumeric; weight = 1; level = 'standard' }
            'datetime-conversion' = @{ pattern = $script:DataQualityPatterns.toDatetime; weight = 1; level = 'standard' }
            'string-cleaning' = @{ pattern = $script:DataQualityPatterns.strReplace; weight = 1; level = 'standard' }
            'string-trimming' = @{ pattern = $script:DataQualityPatterns.strStrip; weight = 1; level = 'standard' }
            'range-clipping' = @{ pattern = $script:DataQualityPatterns.clip; weight = 1; level = 'comprehensive' }
            'range-check' = @{ pattern = $script:DataQualityPatterns.between; weight = 1; level = 'comprehensive' }
        }
        
        # Check each pattern
        foreach ($patternName in $patternsToCheck.Keys) {
            $pattern = $patternsToCheck[$patternName]
            
            # Skip if check level doesn't include this pattern
            if (($CheckLevel -eq 'basic' -and $pattern.level -ne 'basic') -or
                ($CheckLevel -eq 'standard' -and $pattern.level -eq 'comprehensive')) {
                continue
            }
            
            $result.maxScore += $pattern.weight
            $found = [regex]::IsMatch($Content, $pattern.pattern)
            
            if ($found) {
                $result.foundPatterns += $patternName
                $result.score += $pattern.weight
            }
            else {
                $result.missingPatterns += $patternName
            }
        }
        
        # Generate recommendations
        if ('null-check' -notin $result.foundPatterns) {
            $result.recommendations += "Consider adding null/missing value checks using .isnull() or .isna()"
        }
        if ('duplicate-check' -notin $result.foundPatterns) {
            $result.recommendations += "Consider checking for duplicate rows using .duplicated() or .drop_duplicates()"
        }
        if ('type-conversion' -notin $result.foundPatterns -and 'numeric-conversion' -notin $result.foundPatterns) {
            $result.recommendations += "Consider validating data types and converting when necessary"
        }
        if ('string-cleaning' -notin $result.foundPatterns) {
            $result.recommendations += "Consider string cleaning operations if working with text data"
        }
        
        # Calculate percentage score
        $result.scorePercentage = if ($result.maxScore -gt 0) { 
            [math]::Round(($result.score / $result.maxScore) * 100, 2) 
        } else { 
            0 
        }
        
        # Overall quality rating
        $result.rating = switch ($result.scorePercentage) {
            { $_ -ge 80 } { 'Excellent' }
            { $_ -ge 60 } { 'Good' }
            { $_ -ge 40 } { 'Fair' }
            { $_ -ge 20 } { 'Needs Improvement' }
            default { 'Poor' }
        }
        
        return $result
    }
    catch {
        Write-Error "[Test-DataQualityPattern] Failed to validate patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Detects Mito-specific patterns in code.

.DESCRIPTION
    Identifies code related to the Mito spreadsheet interface including
    sheet imports, transformations, and generated code patterns.

.PARAMETER Path
    Path to the Python file to analyze.

.PARAMETER Content
    Python code string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Mito pattern detection results.

.EXAMPLE
    $mito = Get-MitoPatterns -Path "analysis.py"
#>
function Get-MitoPatterns {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $result = @{
            hasMitoCode = $false
            sheetImports = @()
            transformations = @()
            generatedCodeBlocks = @()
            undoRedoCalls = @()
        }
        
        # Check for Mito code
        if ($Content -match 'mitosheet|mito') {
            $result.hasMitoCode = $true
        }
        
        # Find sheet imports
        $sheetMatches = [regex]::Matches($Content, $script:MitoPatterns.importSheet)
        foreach ($match in $sheetMatches) {
            $result.sheetImports += @{
                line = $match.Value
                position = $match.Index
            }
        }
        
        # Find transformations
        $transformMatches = [regex]::Matches($Content, $script:MitoPatterns.runTransform)
        foreach ($match in $transformMatches) {
            $result.transformations += @{
                transform = $match.Groups['transform'].Value
                matchedText = $match.Value
            }
        }
        
        # Find generated code blocks
        $generatedMatches = [regex]::Matches($Content, $script:MitoPatterns.generatedCode)
        $result.generatedCodeBlockCount = $generatedMatches.Count
        
        # Find undo/redo
        if ($Content -match $script:MitoPatterns.undo) {
            $result.undoRedoCalls += 'undo'
        }
        if ($Content -match $script:MitoPatterns.redo) {
            $result.undoRedoCalls += 'redo'
        }
        if ($Content -match $script:MitoPatterns.clear) {
            $result.undoRedoCalls += 'clear'
        }
        
        return $result
    }
    catch {
        Write-Error "[Get-MitoPatterns] Failed to detect Mito patterns: $_"
        return $null
    }
}

# Export module members
if ($MyInvocation.InvocationName -ne ".") { Export-ModuleMember -Function @(
    'Get-DataFrameOperations',
    'Get-DataTransformPatterns',
    'Get-VisualizationCode',
    'New-DataLineageMap',
    'Test-DataQualityPattern',
    'Get-MitoPatterns'
)

}

