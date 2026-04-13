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
    
    This parser implements Section 25.15.1 of the canonical architecture
    for the Notebook/Data Workflow pack's structured extraction pipeline.

.NOTES
    File Name      : NotebookParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Format Support : Jupyter Notebook Format 4.x
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants and Patterns
# ============================================================================

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
        'application/vnd.jupyter.widget-view+json',
        'application/vnd.jupyter.widget-state+json',
        'text/html',
        'image/svg+xml',
        'image/png',
        'image/jpeg',
        'image/gif',
        'text/markdown',
        'text/latex',
        'application/javascript',
        'application/json',
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
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Parses a Jupyter Notebook file (.ipynb).

.DESCRIPTION
    Main entry point for parsing Jupyter notebooks. Extracts all cells,
    metadata, outputs, and widget state following the Phase 4 Structured
    Extraction Pipeline schema.

.PARAMETER Path
    Path to the .ipynb file to parse.

.PARAMETER Content
    JSON content string (alternative to Path).

.PARAMETER IncludeRawContent
    If specified, includes the raw JSON content in the output.

.OUTPUTS
    System.Collections.Hashtable. Complete extraction with cells array and metadata.

.EXAMPLE
    $result = ConvertFrom-JupyterNotebook -Path "analysis.ipynb"

.EXAMPLE
    $json = Get-Content -Raw "notebook.ipynb"
    $result = ConvertFrom-JupyterNotebook -Content $json
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
        # Load content from file if path provided
        $filePath = ''
        $rawContent = ''
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[ConvertFrom-JupyterNotebook] Loading file: $Path"
            
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Error "File not found: $Path"
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
            Write-Error "Content is empty"
            return $null
        }
        
        # Validate JSON
        if (-not (Test-ValidJson -Content $rawContent)) {
            Write-Error "Invalid JSON content"
            return $null
        }
        
        Write-Verbose "[ConvertFrom-JupyterNotebook] Parsing notebook ($($rawContent.Length) chars)"
        
        # Parse JSON
        $notebook = $rawContent | ConvertFrom-Json
        
        # Validate notebook format
        if ($notebook.nbformat -lt 3) {
            Write-Warning "Unsupported notebook format version: $($notebook.nbformat)"
        }
        
        # Extract notebook metadata
        $notebookMetadata = @{
            kernelspec = $null
            languageInfo = $null
            widgets = $null
            raw = $notebook.metadata
        }
        
        if ($notebook.metadata) {
            if ($notebook.metadata.kernelspec) {
                $notebookMetadata.kernelspec = @{
                    displayName = $notebook.metadata.kernelspec.display_name
                    language = $notebook.metadata.kernelspec.language
                    name = $notebook.metadata.kernelspec.name
                }
            }
            
            if ($notebook.metadata.language_info) {
                $notebookMetadata.languageInfo = @{
                    name = $notebook.metadata.language_info.name
                    version = $notebook.metadata.language_info.version
                    mimetype = $notebook.metadata.language_info.mimetype
                    fileExtension = $notebook.metadata.language_info.file_extension
                }
            }
            
            # Extract widget state
            if ($notebook.metadata.widgets) {
                $notebookMetadata.widgets = ConvertFrom-WidgetState -WidgetState $notebook.metadata.widgets
            }
        }
        
        # Extract cells
        $cells = @()
        $cellIndex = 0
        
        foreach ($cell in $notebook.cells) {
            $cellType = $cell.cell_type
            $source = Get-CellSourceContent -Source $cell.source
            $metadata = $cell.metadata
            $outputs = $cell.outputs
            $executionCount = $cell.execution_count
            
            $parsedCell = New-NotebookCell `
                -CellType $cellType `
                -Source $source `
                -CellIndex $cellIndex `
                -Metadata $metadata `
                -Outputs $outputs `
                -ExecutionCount $executionCount
            
            $cells += $parsedCell
            $cellIndex++
        }
        
        # Build final result
        $result = @{
            fileType = 'jupyter-notebook'
            filePath = $filePath
            nbformat = $notebook.nbformat
            nbformatMinor = $notebook.nbformat_minor
            metadata = $notebookMetadata
            cells = $cells
            cellCounts = @{
                total = $cells.Count
                code = ($cells | Where-Object { $_.cellType -eq 'code' }).Count
                markdown = ($cells | Where-Object { $_.cellType -eq 'markdown' }).Count
                raw = ($cells | Where-Object { $_.cellType -eq 'raw' }).Count
                withOutputs = ($cells | Where-Object { $_.hasOutputs }).Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        if ($IncludeRawContent) {
            $result.rawContent = $rawContent
        }
        
        Write-Verbose "[ConvertFrom-JupyterNotebook] Parsing complete: $($cells.Count) cells extracted"
        
        return $result
    }
    catch {
        Write-Error "[ConvertFrom-JupyterNotebook] Failed to parse notebook: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts cells from a parsed notebook by type.

.DESCRIPTION
    Filters cells from a parsed notebook based on cell type and other criteria.

.PARAMETER Notebook
    The parsed notebook object from ConvertFrom-JupyterNotebook.

.PARAMETER CellType
    The type of cells to extract (code, markdown, raw).

.PARAMETER HasOutputs
    If specified, filters cells based on whether they have outputs.

.OUTPUTS
    System.Array. Array of cell objects matching the criteria.

.EXAMPLE
    $cells = Get-NotebookCells -Notebook $notebook -CellType 'code'

.EXAMPLE
    $markdownCells = Get-NotebookCells -Notebook $notebook -CellType 'markdown'
#>
function Get-NotebookCells {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Notebook,
        
        [Parameter()]
        [ValidateSet('code', 'markdown', 'raw', 'all')]
        [string]$CellType = 'all',
        
        [Parameter()]
        [switch]$HasOutputs
    )
    
    process {
        if (-not $Notebook.cells) {
            return @()
        }
        
        $cells = $Notebook.cells
        
        # Filter by cell type
        if ($CellType -ne 'all') {
            $cells = $cells | Where-Object { $_.cellType -eq $CellType }
        }
        
        # Filter by outputs
        if ($HasOutputs) {
            $cells = $cells | Where-Object { $_.hasOutputs }
        }
        
        return $cells
    }
}

<#
.SYNOPSIS
    Extracts code cell content from a notebook.

.DESCRIPTION
    Returns just the source code from code cells, optionally with metadata.

.PARAMETER Notebook
    The parsed notebook object or path to .ipynb file.

.PARAMETER IncludeLineNumbers
    If specified, includes line number information.

.OUTPUTS
    System.Array. Array of code strings or objects with metadata.

.EXAMPLE
    $code = Get-NotebookCode -Notebook $notebook

.EXAMPLE
    Get-NotebookCode -Notebook $notebook -IncludeLineNumbers
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
            # Load notebook if path provided
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Notebook = ConvertFrom-JupyterNotebook -Path $Path
                if (-not $Notebook) {
                    return @()
                }
            }
            
            $codeCells = Get-NotebookCells -Notebook $Notebook -CellType 'code'
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
            Write-Error "[Get-NotebookCode] Failed to extract code: $_"
            return @()
        }
    }
}

<#
.SYNOPSIS
    Extracts cell outputs from a notebook.

.DESCRIPTION
    Returns all outputs from code cells, optionally filtered by output type.

.PARAMETER Notebook
    The parsed notebook object or path to .ipynb file.

.PARAMETER OutputType
    Filter by output type (stream, display_data, execute_result, error).

.PARAMETER IncludeData
    If specified, includes full output data (can be large).

.OUTPUTS
    System.Array. Array of output objects.

.EXAMPLE
    $outputs = Get-NotebookOutputs -Notebook $notebook

.EXAMPLE
    Get-NotebookOutputs -Notebook $notebook -OutputType 'display_data'
#>
function Get-NotebookOutputs {
    [CmdletBinding(DefaultParameterSetName = 'Notebook')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Notebook', Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Notebook,
        
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('stream', 'display_data', 'execute_result', 'error', 'update_display_data', 'all')]
        [string]$OutputType = 'all',
        
        [Parameter()]
        [switch]$IncludeData
    )
    
    process {
        try {
            # Load notebook if path provided
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Notebook = ConvertFrom-JupyterNotebook -Path $Path
                if (-not $Notebook) {
                    return @()
                }
            }
            
            $codeCells = Get-NotebookCells -Notebook $Notebook -CellType 'code'
            $result = @()
            
            foreach ($cell in $codeCells) {
                if ($cell.outputs.Count -eq 0) {
                    continue
                }
                
                foreach ($output in $cell.outputs) {
                    if ($OutputType -ne 'all' -and $output.outputType -ne $OutputType) {
                        continue
                    }
                    
                    $outputInfo = @{
                        cellIndex = $cell.cellIndex
                        cellExecutionCount = $cell.executionCount
                        outputType = $output.outputType
                    }
                    
                    if ($IncludeData) {
                        $outputInfo.output = $output
                    }
                    else {
                        # Include summary only
                        $outputInfo.summary = switch ($output.outputType) {
                            'stream' { "Stream ($($output.name)): $($output.text.Substring(0, [Math]::Min(100, $output.text.Length)))..." }
                            'error' { "Error: $($output.ename) - $($output.evalue)" }
                            default { "Output: $($output.primaryMimeType)" }
                        }
                    }
                    
                    $result += $outputInfo
                }
            }
            
            return $result
        }
        catch {
            Write-Error "[Get-NotebookOutputs] Failed to extract outputs: $_"
            return @()
        }
    }
}

<#
.SYNOPSIS
    Validates the integrity of a notebook structure.

.DESCRIPTION
    Checks if a notebook file is valid and complete, detecting common issues
    like missing cells, invalid JSON, corrupted outputs, etc.

.PARAMETER Path
    Path to the .ipynb file to validate.

.PARAMETER Notebook
    The parsed notebook object to validate.

.PARAMETER Strict
    If specified, performs stricter validation checks.

.OUTPUTS
    System.Collections.Hashtable. Validation result with status and issues.

.EXAMPLE
    $validation = Test-NotebookIntegrity -Path "analysis.ipynb"

.EXAMPLE
    $notebook | Test-NotebookIntegrity -Strict
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
            # Load notebook if path provided
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
                
                $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
                
                # Validate JSON
                if (-not (Test-ValidJson -Content $rawContent)) {
                    return @{
                        isValid = $false
                        status = 'InvalidJson'
                        issues = @("File contains invalid JSON")
                        warnings = @()
                        cellCount = 0
                        executionOrder = @()
                    }
                }
                
                $Notebook = ConvertFrom-JupyterNotebook -Path $Path
                if (-not $Notebook) {
                    return @{
                        isValid = $false
                        status = 'ParseError'
                        issues = @("Failed to parse notebook")
                        warnings = @()
                        cellCount = 0
                        executionOrder = @()
                    }
                }
            }
            
            # Check notebook structure
            if (-not $Notebook.cells) {
                $issues += "Notebook has no cells"
            }
            elseif ($Notebook.cells.Count -eq 0) {
                $warnings += "Notebook is empty (no cells)"
            }
            
            # Check for required fields
            if (-not $Notebook.nbformat) {
                $issues += "Missing nbformat field"
            }
            elseif ($Notebook.nbformat -lt 3) {
                $warnings += "Legacy notebook format ($($Notebook.nbformat))"
            }
            
            # Validate cells
            $cellIndex = 0
            $executionCounts = @()
            $executionOrder = @()
            
            foreach ($cell in $Notebook.cells) {
                if (-not $cell.cellType) {
                    $issues += "Cell $cellIndex missing cell_type"
                }
                elseif ($cell.cellType -notin $script:CellTypes) {
                    $issues += "Cell $cellIndex has invalid cell_type: $($cell.cellType)"
                }
                
                # Check for source
                if (-not $cell.source -and $cell.source -ne '') {
                    $warnings += "Cell $cellIndex missing source field"
                }
                
                # Validate code cells
                if ($cell.cellType -eq 'code') {
                    if ($null -ne $cell.executionCount) {
                        $executionCounts += $cell.executionCount
                        $executionOrder += @{
                            cellIndex = $cellIndex
                            executionCount = $cell.executionCount
                        }
                        
                        # Check for execution count consistency in strict mode
                        if ($Strict -and $cell.executionCount -lt 1 -and $cell.hasOutputs) {
                            $warnings += "Cell $cellIndex has outputs but execution_count is $($cell.executionCount)"
                        }
                    }
                }
                
                $cellIndex++
            }
            
            # Check execution order
            if ($executionCounts.Count -gt 0) {
                $sorted = $executionCounts | Sort-Object
                for ($i = 1; $i -lt $sorted.Count; $i++) {
                    if ($sorted[$i] -lt $sorted[$i - 1]) {
                        $warnings += "Cell execution order appears non-linear"
                        break
                    }
                }
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
                cellCount = $Notebook.cells.Count
                codeCellCount = ($Notebook.cells | Where-Object { $_.cellType -eq 'code' }).Count
                markdownCellCount = ($Notebook.cells | Where-Object { $_.cellType -eq 'markdown' }).Count
                executionOrder = $executionOrder
                checkedAt = [DateTime]::UtcNow.ToString("o")
            }
        }
        catch {
            Write-Error "[Test-NotebookIntegrity] Validation error: $_"
            return @{
                isValid = $false
                status = 'Error'
                issues = @("Validation error: $_")
                warnings = @()
                cellCount = 0
                executionOrder = @()
            }
        }
    }
}

<#
.SYNOPSIS
    Gets widget state from a parsed notebook.

.DESCRIPTION
    Extracts widget state information if present in the notebook metadata.

.PARAMETER Notebook
    The parsed notebook object or path to .ipynb file.

.OUTPUTS
    System.Collections.Hashtable. Widget state information or null.

.EXAMPLE
    $widgets = Get-NotebookWidgetState -Notebook $notebook
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
            # Load notebook if path provided
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Notebook = ConvertFrom-JupyterNotebook -Path $Path
                if (-not $Notebook) {
                    return $null
                }
            }
            
            if ($Notebook.metadata -and $Notebook.metadata.widgets) {
                return $Notebook.metadata.widgets
            }
            
            return $null
        }
        catch {
            Write-Error "[Get-NotebookWidgetState] Failed to extract widget state: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Gets cell execution order information.

.DESCRIPTION
    Extracts execution count information from code cells to analyze
    execution order and identify potential issues.

.PARAMETER Notebook
    The parsed notebook object or path to .ipynb file.

.OUTPUTS
    System.Collections.Hashtable. Execution order analysis.

.EXAMPLE
    $execOrder = Get-NotebookExecutionOrder -Notebook $notebook
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
            # Load notebook if path provided
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Notebook = ConvertFrom-JupyterNotebook -Path $Path
                if (-not $Notebook) {
                    return $null
                }
            }
            
            $codeCells = Get-NotebookCells -Notebook $Notebook -CellType 'code'
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
            Write-Error "[Get-NotebookExecutionOrder] Failed to get execution order: $_"
            return $null
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'ConvertFrom-JupyterNotebook',
    'Get-NotebookCells',
    'Get-NotebookCode',
    'Get-NotebookOutputs',
    'Test-NotebookIntegrity',
    'Get-NotebookWidgetState',
    'Get-NotebookExecutionOrder'
)
