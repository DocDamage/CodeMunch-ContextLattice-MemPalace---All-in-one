#requires -Version 5.1
<#
.SYNOPSIS
    Jupyter Notebook parser for LLM Workflow Structured Extraction Pipeline.

.DESCRIPTION
    Parses Jupyter Notebook files (.ipynb) and extracts structured metadata including:
    - Code cells with source content
    - Markdown cells with documentation
    - Raw cells
    - Cell outputs (text, images, HTML, JavaScript)
    - Cell execution order and execution counts
    - Widget state and metadata
    - Notebook metadata (kernelspec, language_info, etc.)
    - Cell tags and attachments
    
    Also provides conversion from notebook to executable script.
    
    This parser implements Section 25.6 of the canonical architecture
    for the Notebook/Data Workflow pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Extract-NotebookCells: Extract code and markdown cells
    - Extract-NotebookOutputs: Extract cell outputs
    - Extract-NotebookMetadata: Extract kernel and language metadata
    - Convert-NotebookToScript: Convert notebook to executable script

.PARAMETER Path
    Path to the .ipynb file to parse.

.PARAMETER Content
    JSON content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw JSON content in the output.

.OUTPUTS
    JSON with cell arrays, outputs, metadata, and provenance information.

.NOTES
    File Name      : NotebookParser.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Format Support : Jupyter Notebook Format 4.x
    Pack           : notebook-data
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'NotebookParser'

# Supported cell types
$script:CellTypes = @('code', 'markdown', 'raw')

# Supported output types
$script:OutputTypes = @('stream', 'display_data', 'execute_result', 'error', 'update_display_data')

# MIME types for rich output
$script:MimeTypes = @{
    text = 'text/plain'
    html = 'text/html'
    markdown = 'text/markdown'
    latex = 'text/latex'
    json = 'application/json'
    javascript = 'application/javascript'
    png = 'image/png'
    jpeg = 'image/jpeg'
    svg = 'image/svg+xml'
    gif = 'image/gif'
    pdf = 'application/pdf'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

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
    Validates if content is valid JSON.
.DESCRIPTION
    Internal helper to validate JSON structure before parsing.
.PARAMETER Content
    The content to validate.
.OUTPUTS
    System.Boolean. True if valid JSON, false otherwise.
#>
function Test-ValidJson {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    try {
        $null = $Content | ConvertFrom-Json -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Extracts the cell source content.
.DESCRIPTION
    Handles both single string and array of strings (multiline) source formats.
.PARAMETER Source
    The source object from the cell.
.OUTPUTS
    System.String. The concatenated source content.
#>
function Get-CellSourceContent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Source
    )
    
    if ($Source -is [string]) {
        return $Source
    }
    elseif ($Source -is [array]) {
        return $Source -join ""
    }
    else {
        return [string]$Source
    }
}

<#
.SYNOPSIS
    Parses cell metadata into a structured object.
.DESCRIPTION
    Extracts tags, execution timing, and other metadata from cell metadata.
.PARAMETER Metadata
    The metadata hashtable from the cell.
.OUTPUTS
    System.Collections.Hashtable. Structured metadata object.
#>
function ConvertFrom-CellMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Metadata
    )
    
    $result = @{
        tags = @()
        scrolled = $false
        collapsed = $false
        deletable = $true
        editable = $true
        execution = @{}
    }
    
    if ($null -eq $Metadata) {
        return $result
    }
    
    # Extract tags
    if ($Metadata.tags) {
        $result.tags = @($Metadata.tags)
    }
    
    # Jupyter-specific metadata
    if ($Metadata.scrolled) {
        $result.scrolled = $Metadata.scrolled
    }
    if ($Metadata.collapsed) {
        $result.collapsed = [bool]$Metadata.collapsed
    }
    if ($PSBoundParameters.ContainsKey('deletable')) {
        $result.deletable = [bool]$Metadata.deletable
    }
    if ($PSBoundParameters.ContainsKey('editable')) {
        $result.editable = [bool]$Metadata.editable
    }
    
    # Execution metadata
    if ($Metadata.execution) {
        $result.execution = @{
            iopub.status.busy = $Metadata.execution.'iopub.status.busy'
            iopub.status.idle = $Metadata.execution.'iopub.status.idle'
            iopub.execute_input = $Metadata.execution.'iopub.execute_input'
            shell.execute_reply = $Metadata.execution.'shell.execute_reply'
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Parses cell outputs into structured objects.
.DESCRIPTION
    Extracts output content based on output type (stream, display_data, execute_result, error).
.PARAMETER Outputs
    The outputs array from the cell.
.OUTPUTS
    System.Array. Array of structured output objects.
#>
function ConvertFrom-CellOutputs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Outputs
    )
    
    $result = @()
    
    foreach ($output in $Outputs) {
        $outputType = $output.output_type
        $parsedOutput = @{
            outputType = $outputType
            executionCount = $output.execution_count
        }
        
        switch ($outputType) {
            'stream' {
                $parsedOutput.name = $output.name  # stdout or stderr
                $parsedOutput.text = Get-CellSourceContent -Source $output.text
            }
            
            { $_ -in @('display_data', 'execute_result', 'update_display_data') } {
                $parsedOutput.data = @{}
                $parsedOutput.metadata = $output.metadata
                
                if ($output.data) {
                    foreach ($mimeType in $output.data.PSObject.Properties.Name) {
                        $parsedOutput.data[$mimeType] = Get-CellSourceContent -Source $output.data.$mimeType
                    }
                }
                
                # Extract primary content for convenience
                $primaryMime = Get-PrimaryMimeType -Data $parsedOutput.data
                if ($primaryMime) {
                    $parsedOutput.primaryContent = $parsedOutput.data[$primaryMime]
                    $parsedOutput.primaryMimeType = $primaryMime
                }
            }
            
            'error' {
                $parsedOutput.ename = $output.ename
                $parsedOutput.evalue = $output.evalue
                $parsedOutput.traceback = $output.traceback
            }
        }
        
        $result += $parsedOutput
    }
    
    return $result
}

<#
.SYNOPSIS
    Determines the primary MIME type from output data.
.DESCRIPTION
    Selects the richest MIME type for display purposes.
.PARAMETER Data
    The data hashtable containing MIME type keys.
.OUTPUTS
    System.String. The primary MIME type or null.
#>
function Get-PrimaryMimeType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    if ($Data.Count -eq 0) {
        return $null
    }
    
    # Priority order for MIME types
    $priorityOrder = @(
        'application/vnd.jupyter.widget-view+json'
        'application/vnd.jupyter.widget-state+json'
        'text/html'
        'image/svg+xml'
        'image/png'
        'image/jpeg'
        'image/gif'
        'text/markdown'
        'text/latex'
        'application/javascript'
        'application/json'
        'text/plain'
    )
    
    foreach ($mime in $priorityOrder) {
        if ($Data.ContainsKey($mime)) {
            return $mime
        }
    }
    
    # Return first available if none in priority list
    return $Data.Keys | Select-Object -First 1
}

<#
.SYNOPSIS
    Extracts widget state from notebook.
.DESCRIPTION
    Parses widget state metadata and version information.
.PARAMETER WidgetState
    The widget state object from the notebook metadata.
.OUTPUTS
    System.Collections.Hashtable. Structured widget state.
#>
function ConvertFrom-WidgetState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$WidgetState
    )
    
    $result = @{
        versionMajor = 2
        versionMinor = 0
        state = @{}
        widgets = @()
    }
    
    if ($null -eq $WidgetState) {
        return $result
    }
    
    if ($WidgetState.version) {
        $result.versionMajor = $WidgetState.version[0]
        $result.versionMinor = $WidgetState.version[1]
    }
    
    if ($WidgetState.state) {
        $result.state = $WidgetState.state
        
        # Extract individual widget states
        if ($WidgetState.state.state) {
            foreach ($widgetId in $WidgetState.state.state.PSObject.Properties.Name) {
                $widget = $WidgetState.state.state.$widgetId
                $result.widgets += @{
                    id = $widgetId
                    modelName = $widget.model_name
                    modelModule = $widget.model_module
                    modelModuleVersion = $widget.model_module_version
                    state = $widget.state
                }
            }
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Creates a structured cell object.
.DESCRIPTION
    Factory function to create standardized cell objects.
.PARAMETER CellType
    The type of cell (code, markdown, raw).
.PARAMETER Source
    The cell source content.
.PARAMETER CellIndex
    The index of the cell in the notebook.
.PARAMETER Metadata
    The cell metadata.
.PARAMETER Outputs
    The cell outputs (for code cells).
.PARAMETER ExecutionCount
    The execution count (for code cells).
.OUTPUTS
    System.Collections.Hashtable. Structured cell object.
#>
function New-NotebookCell {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('code', 'markdown', 'raw')]
        [string]$CellType,
        
        [Parameter(Mandatory = $true)]
        [string]$Source,
        
        [Parameter(Mandatory = $true)]
        [int]$CellIndex,
        
        [Parameter()]
        [object]$Metadata = $null,
        
        [Parameter()]
        [array]$Outputs = @(),
        
        [Parameter()]
        [int]$ExecutionCount = $null
    )
    
    $cell = @{
        cellType = $CellType
        source = $Source
        cellIndex = $CellIndex
        metadata = ConvertFrom-CellMetadata -Metadata $Metadata
        outputs = @()
        executionCount = $ExecutionCount
        hasOutputs = $Outputs.Count -gt 0
        lineCount = ($Source -split "`r?`n").Count
        charCount = $Source.Length
    }
    
    if ($CellType -eq 'code' -and $Outputs.Count -gt 0) {
        $cell.outputs = ConvertFrom-CellOutputs -Outputs $Outputs
    }
    
    return $cell
}

# ============================================================================
# Public API Functions - Required by Canonical Document Section 25.6
# ============================================================================

<#
.SYNOPSIS
    Extracts cells from a Jupyter notebook.

.DESCRIPTION
    Parses a Jupyter Notebook file and extracts code, markdown, and raw cells
    with their metadata, outputs, and execution information.

.PARAMETER Path
    Path to the .ipynb file to parse.

.PARAMETER Content
    JSON content string (alternative to Path).

.PARAMETER CellType
    Filter by cell type (code, markdown, raw, all).

.PARAMETER HasOutputs
    If specified, only returns cells with outputs.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - cells: Array of cell objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $cells = Extract-NotebookCells -Path "analysis.ipynb"
    
    $cells = Extract-NotebookCells -Path "analysis.ipynb" -CellType 'code'
#>
function Extract-NotebookCells {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('code', 'markdown', 'raw', 'all')]
        [string]$CellType = 'all',
        
        [Parameter()]
        [switch]$HasOutputs
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[$script:ParserName] Loading notebook: $Path"
            
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    cells = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ totalCells = 0; codeCells = 0; markdownCells = 0 }
                }
            }
            
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                cells = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ totalCells = 0; codeCells = 0; markdownCells = 0 }
            }
        }
        
        # Validate JSON
        if (-not (Test-ValidJson -Content $Content)) {
            return @{
                cells = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Invalid JSON content")
                statistics = @{ totalCells = 0; codeCells = 0; markdownCells = 0 }
            }
        }
        
        # Parse JSON
        $notebook = $Content | ConvertFrom-Json
        
        # Extract cells
        $cells = @()
        $cellIndex = 0
        
        foreach ($cell in $notebook.cells) {
            $type = $cell.cell_type
            $source = Get-CellSourceContent -Source $cell.source
            $metadata = $cell.metadata
            $outputs = $cell.outputs
            $executionCount = $cell.execution_count
            
            # Create cell object
            $parsedCell = New-NotebookCell `
                -CellType $type `
                -Source $source `
                -CellIndex $cellIndex `
                -Metadata $metadata `
                -Outputs $outputs `
                -ExecutionCount $executionCount
            
            # Filter by cell type
            if ($CellType -ne 'all' -and $parsedCell.cellType -ne $CellType) {
                $cellIndex++
                continue
            }
            
            # Filter by outputs
            if ($HasOutputs -and -not $parsedCell.hasOutputs) {
                $cellIndex++
                continue
            }
            
            $cells += $parsedCell
            $cellIndex++
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($cells.Count) cells"
        
        return @{
            cells = $cells
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                totalCells = $cells.Count
                codeCells = ($cells | Where-Object { $_.cellType -eq 'code' }).Count
                markdownCells = ($cells | Where-Object { $_.cellType -eq 'markdown' }).Count
                rawCells = ($cells | Where-Object { $_.cellType -eq 'raw' }).Count
                cellsWithOutputs = ($cells | Where-Object { $_.hasOutputs }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract notebook cells: $_"
        return @{
            cells = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ totalCells = 0; codeCells = 0; markdownCells = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts cell outputs from a Jupyter notebook.

.DESCRIPTION
    Parses a Jupyter Notebook file and extracts all cell outputs,
    optionally filtered by output type.

.PARAMETER Path
    Path to the .ipynb file to parse.

.PARAMETER Content
    JSON content string (alternative to Path).

.PARAMETER OutputType
    Filter by output type (stream, display_data, execute_result, error, all).

.PARAMETER IncludeData
    If specified, includes full output data (can be large).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - outputs: Array of output objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $outputs = Extract-NotebookOutputs -Path "analysis.ipynb"
    
    $outputs = Extract-NotebookOutputs -Path "analysis.ipynb" -OutputType 'display_data'
#>
function Extract-NotebookOutputs {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('stream', 'display_data', 'execute_result', 'error', 'update_display_data', 'all')]
        [string]$OutputType = 'all',
        
        [Parameter()]
        [switch]$IncludeData
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    outputs = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ totalOutputs = 0; errorCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                outputs = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ totalOutputs = 0; errorCount = 0 }
            }
        }
        
        # Validate JSON
        if (-not (Test-ValidJson -Content $Content)) {
            return @{
                outputs = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Invalid JSON content")
                statistics = @{ totalOutputs = 0; errorCount = 0 }
            }
        }
        
        # Parse notebook
        $notebook = $Content | ConvertFrom-Json
        $result = @()
        
        foreach ($cell in $notebook.cells) {
            if ($cell.cell_type -ne 'code' -or -not $cell.outputs) {
                continue
            }
            
            $cellIndex = [Array]::IndexOf($notebook.cells, $cell)
            
            foreach ($output in $cell.outputs) {
                if ($OutputType -ne 'all' -and $output.output_type -ne $OutputType) {
                    continue
                }
                
                $outputInfo = @{
                    id = [System.Guid]::NewGuid().ToString()
                    cellIndex = $cellIndex
                    cellExecutionCount = $cell.execution_count
                    outputType = $output.output_type
                }
                
                if ($IncludeData) {
                    $outputInfo.output = ConvertFrom-CellOutputs -Outputs @($output)
                }
                else {
                    # Include summary only
                    $outputInfo.summary = switch ($output.output_type) {
                        'stream' { "Stream ($($output.name)): $($output.text[0].Substring(0, [Math]::Min(100, $output.text[0].Length)))..." }
                        'error' { "Error: $($output.ename) - $($output.evalue)" }
                        default { "Output: $(($output.data.PSObject.Properties.Name | Select-Object -First 1))" }
                    }
                }
                
                $result += $outputInfo
            }
        }
        
        return @{
            outputs = $result
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                totalOutputs = $result.Count
                streamOutputs = ($result | Where-Object { $_.outputType -eq 'stream' }).Count
                displayOutputs = ($result | Where-Object { $_.outputType -eq 'display_data' }).Count
                executeResults = ($result | Where-Object { $_.outputType -eq 'execute_result' }).Count
                errorCount = ($result | Where-Object { $_.outputType -eq 'error' }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract notebook outputs: $_"
        return @{
            outputs = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ totalOutputs = 0; errorCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts notebook metadata from a Jupyter notebook.

.DESCRIPTION
    Parses a Jupyter Notebook file and extracts kernel and language metadata,
    including kernelspec, language_info, and widget state.

.PARAMETER Path
    Path to the .ipynb file to parse.

.PARAMETER Content
    JSON content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - metadata: Notebook metadata object
    - kernelspec: Kernel specification
    - languageInfo: Language information
    - widgets: Widget state
    - provenance: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $metadata = Extract-NotebookMetadata -Path "analysis.ipynb"
#>
function Extract-NotebookMetadata {
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
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    metadata = @{}
                    kernelspec = $null
                    languageInfo = $null
                    widgets = $null
                    provenance = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ hasKernelSpec = $false; hasLanguageInfo = $false }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                metadata = @{}
                kernelspec = $null
                languageInfo = $null
                widgets = $null
                provenance = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ hasKernelSpec = $false; hasLanguageInfo = $false }
            }
        }
        
        # Validate JSON
        if (-not (Test-ValidJson -Content $Content)) {
            return @{
                metadata = @{}
                kernelspec = $null
                languageInfo = $null
                widgets = $null
                provenance = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Invalid JSON content")
                statistics = @{ hasKernelSpec = $false; hasLanguageInfo = $false }
            }
        }
        
        # Parse notebook
        $notebook = $Content | ConvertFrom-Json
        
        # Validate notebook format
        if ($notebook.nbformat -lt 3) {
            Write-Warning "[$script:ParserName] Unsupported notebook format version: $($notebook.nbformat)"
        }
        
        # Extract metadata
        $kernelspec = $null
        $languageInfo = $null
        $widgets = $null
        
        if ($notebook.metadata) {
            if ($notebook.metadata.kernelspec) {
                $kernelspec = @{
                    displayName = $notebook.metadata.kernelspec.display_name
                    language = $notebook.metadata.kernelspec.language
                    name = $notebook.metadata.kernelspec.name
                }
            }
            
            if ($notebook.metadata.language_info) {
                $languageInfo = @{
                    name = $notebook.metadata.language_info.name
                    version = $notebook.metadata.language_info.version
                    mimetype = $notebook.metadata.language_info.mimetype
                    fileExtension = $notebook.metadata.language_info.file_extension
                    nbconvertExporter = $notebook.metadata.language_info.nbconvert_exporter
                    pygmentsLexer = $notebook.metadata.language_info.pygments_lexer
                }
            }
            
            # Extract widget state
            if ($notebook.metadata.widgets) {
                $widgets = ConvertFrom-WidgetState -WidgetState $notebook.metadata.widgets
            }
        }
        
        return @{
            metadata = @{
                nbformat = $notebook.nbformat
                nbformatMinor = $notebook.nbformat_minor
                raw = $notebook.metadata
            }
            kernelspec = $kernelspec
            languageInfo = $languageInfo
            widgets = $widgets
            provenance = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                hasKernelSpec = $null -ne $kernelspec
                hasLanguageInfo = $null -ne $languageInfo
                hasWidgets = $null -ne $widgets
                nbformat = $notebook.nbformat
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract notebook metadata: $_"
        return @{
            metadata = @{}
            kernelspec = $null
            languageInfo = $null
            widgets = $null
            provenance = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ hasKernelSpec = $false; hasLanguageInfo = $false }
        }
    }
}

<#
.SYNOPSIS
    Converts a Jupyter notebook to an executable script.

.DESCRIPTION
    Parses a Jupyter Notebook file and converts it to an executable script
    by concatenating code cells. Supports various output formats and options.

.PARAMETER Path
    Path to the .ipynb file to parse.

.PARAMETER Content
    JSON content string (alternative to Path).

.PARAMETER Cells
    Pre-extracted cells (optional).

.PARAMETER OutputFormat
    Output format for the script (python, r, julia, javascript, raw).

.PARAMETER IncludeMarkdown
    If specified, includes markdown cells as comments.

.PARAMETER IncludeMagicCommands
    If specified, includes cell magic commands.

.PARAMETER CellSeparator
    String to use between cells (default: newline).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - script: The generated script content
    - language: Detected language
    - cellCount: Number of code cells included
    - metadata: Provenance metadata

.EXAMPLE
    $script = Convert-NotebookToScript -Path "analysis.ipynb"
    
    $script = Convert-NotebookToScript -Path "analysis.ipynb" -IncludeMarkdown
#>
function Convert-NotebookToScript {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Cells')]
        [array]$Cells,
        
        [Parameter()]
        [ValidateSet('auto', 'python', 'r', 'julia', 'javascript', 'scala', 'raw')]
        [string]$OutputFormat = 'auto',
        
        [Parameter()]
        [switch]$IncludeMarkdown,
        
        [Parameter()]
        [switch]$IncludeMagicCommands,
        
        [Parameter()]
        [string]$CellSeparator = "`n\n"
    )
    
    try {
        $sourceFile = 'inline'
        $cells = @()
        $languageInfo = $null
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                if (-not (Test-Path -LiteralPath $Path)) {
                    return @{
                        script = ''
                        language = 'unknown'
                        cellCount = 0
                        metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    }
                }
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $cellsResult = Extract-NotebookCells -Path $Path -CellType 'all'
                $cells = $cellsResult.cells
                $metadataResult = Extract-NotebookMetadata -Path $Path
                $languageInfo = $metadataResult.languageInfo
            }
            'Content' {
                $cellsResult = Extract-NotebookCells -Content $Content -CellType 'all'
                $cells = $cellsResult.cells
                $metadataResult = Extract-NotebookMetadata -Content $Content
                $languageInfo = $metadataResult.languageInfo
            }
            'Cells' {
                $cells = $Cells
            }
        }
        
        # Determine language
        $language = 'python'
        $commentChar = '#'
        
        if ($languageInfo) {
            $language = $languageInfo.name.ToLower()
        }
        
        if ($OutputFormat -ne 'auto') {
            $language = $OutputFormat
        }
        
        # Set comment character based on language
        switch ($language) {
            'python' { $commentChar = '#' }
            'r' { $commentChar = '#' }
            'julia' { $commentChar = '#' }
            'javascript' { $commentChar = '//' }
            'scala' { $commentChar = '//' }
            'raw' { $commentChar = '#' }
        }
        
        # Build script
        $scriptParts = @()
        $codeCellCount = 0
        
        # Add header comment
        $scriptParts += "$commentChar Generated from Jupyter Notebook"
        $scriptParts += "$commentChar Source: $sourceFile"
        $scriptParts += "$commentChar Generated: $([DateTime]::UtcNow.ToString("o"))"
        $scriptParts += "$commentChar Language: $language"
        $scriptParts += ""
        
        foreach ($cell in $cells) {
            switch ($cell.cellType) {
                'code' {
                    $code = $cell.source
                    
                    # Skip magic commands if not requested
                    if (-not $IncludeMagicCommands -and $code -match '^[%!]') {
                        continue
                    }
                    
                    # Convert magic commands to comments
                    if ($code -match '^[%!]' -and $IncludeMagicCommands) {
                        $code = $code -replace '^([%!].*)', "$commentChar `$1"
                    }
                    
                    $scriptParts += $code
                    $codeCellCount++
                }
                'markdown' {
                    if ($IncludeMarkdown) {
                        $markdownLines = $cell.source -split "`r?`n"
                        $commentedMarkdown = $markdownLines | ForEach-Object { "$commentChar $_" }
                        $scriptParts += ($commentedMarkdown -join "`n")
                    }
                }
                'raw' {
                    # Raw cells are typically ignored in script conversion
                    if ($IncludeMarkdown) {
                        $scriptParts += "$commentChar [Raw cell content omitted]"
                    }
                }
            }
        }
        
        $script = $scriptParts -join $CellSeparator
        
        return @{
            script = $script
            language = $language
            cellCount = $codeCellCount
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to convert notebook to script: $_"
        return @{
            script = ''
            language = 'unknown'
            cellCount = 0
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

# ============================================================================
# Legacy Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Parses a Jupyter Notebook file (.ipynb).
    
    DEPRECATED: Use the specific Extract-* functions instead.

.DESCRIPTION
    Legacy entry point that provides comprehensive notebook parsing.
    Delegates to canonical extraction functions.
#>
function ConvertFrom-JupyterNotebook {
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
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    filePath = $Path
                    success = $false
                    error = "File not found: $Path"
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
        }
        
        # Extract all components
        $cells = Extract-NotebookCells @PSBoundParameters
        $outputs = Extract-NotebookOutputs @PSBoundParameters
        $metadata = Extract-NotebookMetadata @PSBoundParameters
        
        return @{
            fileType = 'jupyter-notebook'
            filePath = $sourceFile
            nbformat = $metadata.metadata.nbformat
            nbformatMinor = $metadata.metadata.nbformatMinor
            metadata = @{
                kernelspec = $metadata.kernelspec
                languageInfo = $metadata.languageInfo
                widgets = $metadata.widgets
                raw = $metadata.metadata.raw
            }
            cells = $cells.cells
            outputs = $outputs.outputs
            cellCounts = $cells.statistics
            provenance = $cells.metadata
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to parse notebook: $_"
        return @{
            filePath = $sourceFile
            success = $false
            error = $_.ToString()
        }
    }
}

<#
.SYNOPSIS
    Gets notebook code cells.
    
    DEPRECATED: Use Extract-NotebookCells with -CellType 'code'.
#>
function Get-NotebookCode {
    [CmdletBinding(DefaultParameterSetName = 'Notebook')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Notebook', Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Notebook,
        
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [switch]$IncludeLineNumbers
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $result = Extract-NotebookCells -Path $Path -CellType 'code'
            }
            else {
                $result = Extract-NotebookCells -Content ($Notebook | ConvertTo-Json -Depth 10) -CellType 'code'
            }
            
            $codeCells = $result.cells
            $result = @()
            $globalLineNumber = 1
            
            foreach ($cell in $codeCells) {
                if ($IncludeLineNumbers) {
                    $lines = $cell.source -split "`r?`n"
                    $result += @{
                        cellIndex = $cell.cellIndex
                        executionCount = $cell.executionCount
                        startLine = $globalLineNumber
                        endLine = $globalLineNumber + $lines.Count - 1
                        source = $cell.source
                        tags = $cell.metadata.tags
                    }
                    $globalLineNumber += $lines.Count
                }
                else {
                    $result += $cell.source
                }
            }
            
            return $result
        }
        catch {
            Write-Error "[$script:ParserName] Failed to extract code: $_"
            return @()
        }
    }
}

<#
.SYNOPSIS
    Gets widget state from a parsed notebook.
    
    DEPRECATED: Use Extract-NotebookMetadata instead.
#>
function Get-NotebookWidgetState {
    [CmdletBinding(DefaultParameterSetName = 'Notebook')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Notebook', Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Notebook,
        
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $result = Extract-NotebookMetadata -Path $Path
            }
            else {
                $result = Extract-NotebookMetadata -Content ($Notebook | ConvertTo-Json -Depth 10)
            }
            
            return $result.widgets
        }
        catch {
            Write-Error "[$script:ParserName] Failed to extract widget state: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Gets cell execution order information.
    
    DEPRECATED: This functionality is now part of Extract-NotebookCells.
#>
function Get-NotebookExecutionOrder {
    [CmdletBinding(DefaultParameterSetName = 'Notebook')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Notebook', Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Notebook,
        
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $result = Extract-NotebookCells -Path $Path -CellType 'code'
            }
            else {
                $result = Extract-NotebookCells -Content ($Notebook | ConvertTo-Json -Depth 10) -CellType 'code'
            }
            
            $codeCells = $result.cells
            $executions = @()
            $maxExecution = 0
            $gaps = @()
            $duplicates = @()
            $executedCells = @()
            $nonExecutedCells = @()
            
            foreach ($cell in $codeCells) {
                $execInfo = @{
                    cellIndex = $cell.cellIndex
                    executionCount = $cell.executionCount
                    hasOutputs = $cell.hasOutputs
                }
                
                if ($cell.executionCount) {
                    $executions += $execInfo
                    $executedCells += $cell.cellIndex
                    
                    if ($cell.executionCount -gt $maxExecution) {
                        $maxExecution = $cell.executionCount
                    }
                    
                    # Check for duplicate execution counts
                    $sameCount = $executions | Where-Object { $_.executionCount -eq $cell.executionCount }
                    if ($sameCount.Count -gt 1) {
                        $duplicates += $cell.executionCount
                    }
                }
                else {
                    $nonExecutedCells += $cell.cellIndex
                }
            }
            
            # Check for gaps in execution
            $executedCounts = $executions | ForEach-Object { $_.executionCount } | Sort-Object -Unique
            for ($i = 1; $i -lt $executedCounts.Count; $i++) {
                if ($executedCounts[$i] -ne $executedCounts[$i - 1] + 1) {
                    $gaps += @{
                        from = $executedCounts[$i - 1]
                        to = $executedCounts[$i]
                    }
                }
            }
            
            return @{
                executions = $executions
                maxExecutionCount = $maxExecution
                executedCellCount = $executedCells.Count
                nonExecutedCellCount = $nonExecutedCells.Count
                executionGaps = $gaps
                duplicateExecutions = $duplicates | Select-Object -Unique
                executedCells = $executedCells
                nonExecutedCells = $nonExecutedCells
                isSequential = ($gaps.Count -eq 0 -and $duplicates.Count -eq 0)
            }
        }
        catch {
            Write-Error "[$script:ParserName] Failed to get execution order: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Validates the integrity of a notebook structure.
    
    DEPRECATED: This is now handled during extraction.
#>
function Test-NotebookIntegrity {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Notebook', Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Notebook,
        
        [Parameter()]
        [switch]$Strict
    )
    
    process {
        $issues = @()
        $warnings = @()
        
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                if (-not (Test-Path -LiteralPath $Path)) {
                    return @{
                        isValid = $false
                        status = 'FileNotFound'
                        issues = @("File not found: $Path")
                        warnings = @()
                        cellCount = 0
                        executionOrder = @()
                    }
                }
                
                $result = Extract-NotebookMetadata -Path $Path
                $cellsResult = Extract-NotebookCells -Path $Path -CellType 'all'
            }
            else {
                $json = $Notebook | ConvertTo-Json -Depth 10
                $result = Extract-NotebookMetadata -Content $json
                $cellsResult = Extract-NotebookCells -Content $json -CellType 'all'
            }
            
            $metadata = $result.metadata
            $cells = $cellsResult.cells
            
            # Check notebook structure
            if ($cells.Count -eq 0) {
                $warnings += "Notebook is empty (no cells)"
            }
            
            # Check for required fields
            if (-not $metadata.nbformat) {
                $issues += "Missing nbformat field"
            }
            elseif ($metadata.nbformat -lt 3) {
                $warnings += "Legacy notebook format ($($metadata.nbformat))"
            }
            
            # Validate cells
            $cellIndex = 0
            $executionCounts = @()
            
            foreach ($cell in $cells) {
                # Check for source
                if ([string]::IsNullOrEmpty($cell.source) -and $cell.source -ne '') {
                    $warnings += "Cell $cellIndex missing source field"
                }
                
                # Validate code cells
                if ($cell.cellType -eq 'code') {
                    if ($null -ne $cell.executionCount) {
                        $executionCounts += $cell.executionCount
                        
                        if ($Strict -and $cell.executionCount -lt 1 -and $cell.hasOutputs) {
                            $warnings += "Cell $cellIndex has outputs but execution_count is $($cell.executionCount)"
                        }
                    }
                }
                
                $cellIndex++
            }
            
            # Determine overall status
            $isValid = $issues.Count -eq 0
            $status = if ($isValid) { 
                if ($warnings.Count -gt 0) { 'ValidWithWarnings' } else { 'Valid' }
            } else { 'Invalid' }
            
            return @{
                isValid = $isValid
                status = $status
                issues = $issues
                warnings = $warnings
                cellCount = $cells.Count
                codeCellCount = ($cells | Where-Object { $_.cellType -eq 'code' }).Count
                markdownCellCount = ($cells | Where-Object { $_.cellType -eq 'markdown' }).Count
                checkedAt = [DateTime]::UtcNow.ToString("o")
            }
        }
        catch {
            Write-Error "[$script:ParserName] Validation error: $_"
            return @{
                isValid = $false
                status = 'Error'
                issues = @("Validation error: $_")
                warnings = @()
                cellCount = 0
            }
        }
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

Export-ModuleMember -Function @(
    # Canonical functions (Section 25.6)
    'Extract-NotebookCells'
    'Extract-NotebookOutputs'
    'Extract-NotebookMetadata'
    'Convert-NotebookToScript'
    # Legacy compatibility functions
    'ConvertFrom-JupyterNotebook'
    'Get-NotebookCode'
    'Get-NotebookWidgetState'
    'Get-NotebookExecutionOrder'
    'Test-NotebookIntegrity'
)
