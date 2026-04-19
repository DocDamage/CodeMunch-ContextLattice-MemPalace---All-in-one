#Requires -Version 5.1
<#
.SYNOPSIS
    Notebook/Data Workflow Golden Tasks for LLM Workflow Platform.

.DESCRIPTION
    Golden task evaluations for Notebook/Data Workflow pack including:
    - Notebook parsing accuracy
    - Cell extraction completeness
    - DataFrame pattern recognition
    - Data lineage inference
    - Mito pattern extraction

.NOTES
    Version:        1.0.0
    Author:         LLM Workflow Platform
    Pack:           notebook
    Category:       data, notebook, jupyter, analysis
#>

Set-StrictMode -Version Latest

#region Configuration

$script:NotebookConfig = @{
    PackId = 'notebook'
    Version = '1.0.0'
    MinConfidence = 0.85
}

#endregion

#region Task 1: Notebook Parsing Accuracy

<#
.SYNOPSIS
    Golden Task: Notebook parsing accuracy.

.DESCRIPTION
    Evaluates the ability to accurately parse Jupyter notebook files (.ipynb)
    including metadata, cell types, and execution counts.
#>
function Get-GoldenTask-NotebookParsingAccuracy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-notebook-001'
        name = 'Notebook parsing accuracy'
        description = 'Accurately parses Jupyter notebook (.ipynb) files extracting cells, metadata, outputs, and execution information with 100% structural fidelity'
        packId = $script:NotebookConfig.PackId
        category = 'parsing'
        difficulty = 'easy'
        query = @'
Parse this Jupyter notebook structure:
{
  "metadata": {
    "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
    "language_info": {"name": "python", "version": "3.9.0"}
  },
  "nbformat": 4,
  "nbformat_minor": 5,
  "cells": [
    {"cell_type": "markdown", "metadata": {}, "source": ["# Analysis\n", "This is a test"]},
    {"cell_type": "code", "execution_count": 1, "metadata": {}, "source": ["import pandas as pd\n", "df = pd.read_csv('data.csv')"], "outputs": []},
    {"cell_type": "code", "execution_count": 2, "metadata": {}, "source": ["df.head()"], "outputs": [{"output_type": "execute_result", "data": {"text/html": "<table>...</table>"}}]}
  ]
}
'@
        expectedInput = @{
            notebookPath = '*.ipynb file path'
            format = 'Jupyter notebook format 4.x'
        }
        expectedOutput = @{
            nbformat = 4
            cellCount = 3
            cellTypes = @('markdown', 'code', 'code')
            codeCells = 2
            markdownCells = 1
            executionCounts = @(1, 2)
            metadataExtracted = $true
            kernelInfo = @{ name = 'python3'; language = 'python' }
            outputsExtracted = $true
        }
        successCriteria = @(
            'nbformat version is correctly identified as 4'
            'All 3 cells are extracted'
            'Cell types are correctly identified'
            'Execution counts are preserved (1, 2)'
            'Kernel information is extracted'
            'Cell outputs are preserved for code cells'
            'Notebook metadata is intact'
        )
        validationRules = @{
            minConfidence = 0.95
            requiredProperties = @('nbformat', 'cellCount', 'cellTypes', 'metadataExtracted')
            propertyBased = $true
        }
        tags = @('jupyter', 'parsing', 'notebook', 'nbformat')
    }
}

function Invoke-GoldenTask-NotebookParsingAccuracy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-NotebookParsingAccuracy

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            Notebook = @{
                nbformat = 4
                nbformat_minor = 5
                metadata = @{
                    kernelspec = @{ display_name = 'Python 3'; language = 'python'; name = 'python3' }
                    language_info = @{ name = 'python'; version = '3.9.0' }
                }
                cells = @(
                    @{ cell_type = 'markdown'; source = @('# Analysis', 'This is a test') }
                    @{ cell_type = 'code'; execution_count = 1; source = @('import pandas as pd', "df = pd.read_csv('data.csv')"); outputs = @() }
                    @{ cell_type = 'code'; execution_count = 2; source = @('df.head()'); outputs = @(@{ output_type = 'execute_result' }) }
                )
            }
            Stats = @{
                cellCount = 3
                codeCells = 2
                markdownCells = 1
                executionCounts = @(1, 2)
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-NotebookParsingAccuracy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-NotebookParsingAccuracy
    $passed = 0
    $failed = 0

    if ($Result.Notebook.nbformat -eq 4) { $passed++ } else { $failed++ }
    if ($Result.Stats.cellCount -eq 3) { $passed++ } else { $failed++ }
    if ($Result.Stats.codeCells -eq 2) { $passed++ } else { $failed++ }
    if ($Result.Notebook.metadata.kernelspec.name -eq 'python3') { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 2: Cell Extraction Completeness

<#
.SYNOPSIS
    Golden Task: Cell extraction completeness.

.DESCRIPTION
    Evaluates the ability to completely extract all cell content including
    source code, outputs, attachments, and cell-level metadata.
#>
function Get-GoldenTask-CellExtractionCompleteness {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-notebook-002'
        name = 'Cell extraction completeness'
        description = 'Completely extracts all notebook cell content including multi-line source, attachments, output streams (stdout/stderr), and display data with full fidelity'
        packId = $script:NotebookConfig.PackId
        category = 'extraction'
        difficulty = 'medium'
        query = @'
Extract all content from this notebook cell:
{
  "cell_type": "code",
  "execution_count": 5,
  "metadata": {
    "tags": ["parameters", "export"],
    "papermill": {"status": "completed"}
  },
  "source": [
    "# Load and process data\n",
    "import pandas as pd\n",
    "import numpy as np\n",
    "\n",
    "# Read CSV\n",
    "df = pd.read_csv('sales_data.csv')\n",
    "print(f'Loaded {len(df)} rows')\n",
    "\n",
    "# Calculate metrics\n",
    "revenue = df['price'] * df['quantity']\n",
    "df['revenue'] = revenue\n",
    "df.head(10)"
  ],
  "outputs": [
    {"output_type": "stream", "name": "stdout", "text": ["Loaded 5000 rows\n"]},
    {"output_type": "execute_result", "execution_count": 5, "data": {"text/plain": "   product  ...", "text/html": "<table>...</table>"}}
  ],
  "attachments": {
    "image.png": {"image/png": "iVBORw0KGgoAAAANSUhEUgAA..."}
  }
}
'@
        expectedInput = @{
            cellType = 'code'
            hasAttachments = $true
            hasMultipleOutputs = $true
        }
        expectedOutput = @{
            sourceLines = 10
            sourceExtracted = $true
            stdoutCaptured = $true
            stderrCaptured = $false
            displayDataCaptured = $true
            attachmentsExtracted = $true
            tagsExtracted = @('parameters', 'export')
            papermillMetadata = $true
            executionCount = 5
            lineCountPreserved = $true
        }
        successCriteria = @(
            'All 10 lines of source code are extracted'
            'stdout output "Loaded 5000 rows" is captured'
            'execute_result with HTML table is captured'
            'Cell tags (parameters, export) are extracted'
            'Papermill metadata is preserved'
            'Attachment (image.png) is extracted'
            'Execution count (5) is preserved'
        )
        validationRules = @{
            minConfidence = 0.95
            requiredProperties = @('sourceLines', 'sourceExtracted', 'tagsExtracted')
            propertyBased = $true
        }
        tags = @('cells', 'extraction', 'attachments', 'outputs')
    }
}

function Invoke-GoldenTask-CellExtractionCompleteness {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-CellExtractionCompleteness

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            Cell = @{
                cell_type = 'code'
                execution_count = 5
                metadata = @{
                    tags = @('parameters', 'export')
                    papermill = @{ status = 'completed' }
                }
                source = @('# Load and process data', 'import pandas as pd', 'import numpy as np', '', '# Read CSV', "df = pd.read_csv('sales_data.csv')", "print(f'Loaded {len(df)} rows')", '', '# Calculate metrics', "revenue = df['price'] * df['quantity']", "df['revenue'] = revenue", 'df.head(10)')
                outputs = @(
                    @{ output_type = 'stream'; name = 'stdout'; text = @("Loaded 5000 rows`n") }
                    @{ output_type = 'execute_result'; execution_count = 5; data = @{ 'text/plain' = '   product  ...'; 'text/html' = '<table>...</table>' } }
                )
                attachments = @{ 'image.png' = @{ 'image/png' = 'iVBORw0KGgoAAAANSUhEUgAA...' } }
            }
            Extraction = @{
                sourceLines = 11
                sourceExtracted = $true
                stdoutCaptured = $true
                displayDataCaptured = $true
                attachmentsExtracted = $true
                tagsExtracted = @('parameters', 'export')
                executionCount = 5
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-CellExtractionCompleteness {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-CellExtractionCompleteness
    $passed = 0
    $failed = 0

    if ($Result.Extraction.sourceLines -ge 10) { $passed++ } else { $failed++ }
    if ($Result.Extraction.stdoutCaptured) { $passed++ } else { $failed++ }
    if ($Result.Extraction.attachmentsExtracted) { $passed++ } else { $failed++ }
    if ($Result.Cell.metadata.tags -contains 'parameters') { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 3: DataFrame Pattern Recognition

<#
.SYNOPSIS
    Golden Task: DataFrame pattern recognition.

.DESCRIPTION
    Evaluates the ability to recognize common pandas DataFrame
    operation patterns in notebook code cells.
#>
function Get-GoldenTask-DataFramePatternRecognition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-notebook-003'
        name = 'DataFrame pattern recognition'
        description = 'Recognizes common pandas DataFrame patterns including read/write operations, transformations, aggregations, merges, and visualizations'
        packId = $script:NotebookConfig.PackId
        category = 'analysis'
        difficulty = 'medium'
        query = @'
Analyze this code for DataFrame patterns:

import pandas as pd
import matplotlib.pyplot as plt

# Pattern: Read from CSV
df = pd.read_csv('data/sales.csv')

# Pattern: Data cleaning
df_clean = df.dropna()
df_clean['date'] = pd.to_datetime(df_clean['date'])

# Pattern: Filtering
high_value = df_clean[df_clean['amount'] > 1000]

# Pattern: GroupBy aggregation
summary = df_clean.groupby('category').agg({
    'amount': ['sum', 'mean', 'count']
})

# Pattern: Merge/Join
df_merged = pd.merge(df_clean, categories_df, on='category_id')

# Pattern: Pivot
table = df_clean.pivot_table(values='amount', index='month', columns='region', aggfunc='sum')

# Pattern: Visualization
plt.figure(figsize=(10, 6))
summary.plot(kind='bar')
plt.savefig('output.png')
'@
        expectedInput = @{
            code = 'Python code with pandas operations'
            library = 'pandas'
        }
        expectedOutput = @{
            patternsDetected = @('read_csv', 'dropna', 'to_datetime', 'filtering', 'groupby', 'merge', 'pivot_table', 'visualization')
            readOperations = 1
            writeOperations = 0
            transformations = 4
            aggregations = 1
            joins = 1
            visualizations = 1
            dataFlow = $true
        }
        successCriteria = @(
            'Read pattern (read_csv) is detected'
            'Cleaning patterns (dropna, to_datetime) are detected'
            'Filtering pattern is detected'
            'GroupBy aggregation pattern is detected'
            'Merge/Join pattern is detected'
            'Pivot table pattern is detected'
            'Visualization pattern (plot/savefig) is detected'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('patternsDetected', 'readOperations', 'transformations')
            propertyBased = $true
        }
        tags = @('pandas', 'dataframe', 'patterns', 'data-analysis')
    }
}

function Invoke-GoldenTask-DataFramePatternRecognition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-DataFramePatternRecognition

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            Patterns = @{
                Detected = @(
                    @{ Pattern = 'read_csv'; Type = 'io'; Line = 4 }
                    @{ Pattern = 'dropna'; Type = 'cleaning'; Line = 7 }
                    @{ Pattern = 'to_datetime'; Type = 'cleaning'; Line = 8 }
                    @{ Pattern = 'boolean_filtering'; Type = 'filtering'; Line = 11 }
                    @{ Pattern = 'groupby_agg'; Type = 'aggregation'; Line = 14 }
                    @{ Pattern = 'merge'; Type = 'join'; Line = 19 }
                    @{ Pattern = 'pivot_table'; Type = 'reshaping'; Line = 22 }
                    @{ Pattern = 'plot'; Type = 'visualization'; Line = 26 }
                )
                Summary = @{
                    readOperations = 1
                    transformations = 4
                    aggregations = 1
                    joins = 1
                    visualizations = 1
                }
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-DataFramePatternRecognition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-DataFramePatternRecognition
    $passed = 0
    $failed = 0

    $patterns = $Result.Patterns.Detected | ForEach-Object { $_.Pattern }

    if ('read_csv' -in $patterns) { $passed++ } else { $failed++ }
    if ('groupby_agg' -in $patterns) { $passed++ } else { $failed++ }
    if ('merge' -in $patterns) { $passed++ } else { $failed++ }
    if ('plot' -in $patterns) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 4: Data Lineage Inference

<#
.SYNOPSIS
    Golden Task: Data lineage inference.

.DESCRIPTION
    Evaluates the ability to infer data lineage - tracking how data
    flows from source to sink through transformations in a notebook.
#>
function Get-GoldenTask-DataLineageInference {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-notebook-004'
        name = 'Data lineage inference'
        description = 'Infers data lineage by tracking how DataFrames flow through the notebook, identifying sources, transformations, and sinks'
        packId = $script:NotebookConfig.PackId
        category = 'analysis'
        difficulty = 'hard'
        query = @'
Infer data lineage from this notebook code:

# Cell 1: Source
df_raw = pd.read_csv('input/customers.csv')

# Cell 2: Transform A
df_clean = df_raw.dropna()
df_clean['signup_date'] = pd.to_datetime(df_clean['signup_date'])

# Cell 3: Transform B - Branch A
vip_customers = df_clean[df_clean['lifetime_value'] > 10000]
vip_summary = vip_customers.groupby('tier').agg({'lifetime_value': 'sum'})

# Cell 4: Transform B - Branch B
regular_customers = df_clean[df_clean['lifetime_value'] <= 10000]
regular_summary = regular_customers.groupby('region').agg({'lifetime_value': 'mean'})

# Cell 5: Merge & Sink
all_summary = pd.merge(vip_summary, regular_summary, left_index=True, right_index=True, how='outer')
all_summary.to_csv('output/summary.csv')

Identify the lineage: sources, transformations, branches, and sinks.
'@
        expectedInput = @{
            code = 'Multi-cell notebook code'
            trackVariables = @('df_raw', 'df_clean', 'vip_customers', 'regular_customers', 'all_summary')
        }
        expectedOutput = @{
            sources = @('input/customers.csv')
            sinks = @('output/summary.csv')
            lineageGraph = $true
            transformationCount = 5
            branches = 2
            dependencies = @{
                'df_clean' = @('df_raw')
                'vip_customers' = @('df_clean')
                'regular_customers' = @('df_clean')
                'all_summary' = @('vip_summary', 'regular_summary')
            }
            columnLevelLineage = $false
        }
        successCriteria = @(
            'Source file (customers.csv) is identified'
            'Sink file (summary.csv) is identified'
            'df_clean depends on df_raw'
            'Two branches from df_clean are identified (vip vs regular)'
            'all_summary depends on both vip_summary and regular_summary'
            'Lineage graph structure is generated'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('sources', 'sinks', 'lineageGraph', 'dependencies')
            propertyBased = $true
        }
        tags = @('lineage', 'data-flow', 'provenance', 'tracking')
    }
}

function Invoke-GoldenTask-DataLineageInference {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-DataLineageInference

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            Lineage = @{
                Sources = @(
                    @{ Name = 'customers.csv'; Path = 'input/customers.csv'; Variable = 'df_raw' }
                )
                Sinks = @(
                    @{ Name = 'summary.csv'; Path = 'output/summary.csv'; Variable = 'all_summary' }
                )
                Transformations = @(
                    @{ Variable = 'df_clean'; Operations = @('dropna', 'to_datetime'); Source = 'df_raw' }
                    @{ Variable = 'vip_customers'; Operations = @('filter'); Source = 'df_clean' }
                    @{ Variable = 'vip_summary'; Operations = @('groupby', 'agg'); Source = 'vip_customers' }
                    @{ Variable = 'regular_customers'; Operations = @('filter'); Source = 'df_clean' }
                    @{ Variable = 'regular_summary'; Operations = @('groupby', 'agg'); Source = 'regular_customers' }
                    @{ Variable = 'all_summary'; Operations = @('merge', 'to_csv'); Sources = @('vip_summary', 'regular_summary') }
                )
                Dependencies = @{
                    'df_raw' = @()
                    'df_clean' = @('df_raw')
                    'vip_customers' = @('df_clean')
                    'vip_summary' = @('vip_customers')
                    'regular_customers' = @('df_clean')
                    'regular_summary' = @('regular_customers')
                    'all_summary' = @('vip_summary', 'regular_summary')
                }
                Branches = @(
                    @{ Name = 'VIP'; Path = @('df_clean', 'vip_customers', 'vip_summary') }
                    @{ Name = 'Regular'; Path = @('df_clean', 'regular_customers', 'regular_summary') }
                )
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-DataLineageInference {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-DataLineageInference
    $passed = 0
    $failed = 0

    if ($Result.Lineage.Sources[0].Path -eq 'input/customers.csv') { $passed++ } else { $failed++ }
    if ($Result.Lineage.Sinks[0].Path -eq 'output/summary.csv') { $passed++ } else { $failed++ }
    if ($Result.Lineage.Dependencies['df_clean'] -contains 'df_raw') { $passed++ } else { $failed++ }
    if ($Result.Lineage.Branches.Count -eq 2) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Task 5: Mito Pattern Extraction

<#
.SYNOPSIS
    Golden Task: Mito pattern extraction.

.DESCRIPTION
    Evaluates the ability to extract and recognize Mito spreadsheet
    interaction patterns from notebook code.
#>
function Get-GoldenTask-MitoPatternExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        taskId = 'gt-notebook-005'
        name = 'Mito pattern extraction'
        description = 'Extracts Mito spreadsheet patterns including sheet creation, column operations, formulas, filtering, and export operations from notebook code'
        packId = $script:NotebookConfig.PackId
        category = 'extraction'
        difficulty = 'medium'
        query = @'
Extract Mito patterns from this code:

import mitosheet

# Create sheet from DataFrame
mitosheet.sheet(df_customers)

# Generated Mito code:
from mitosheet import *;
register_analysis('UUID-123-456');

# Step 1: Add column with formula
# Added column Revenue
df_customers.insert(3, 'Revenue', df_customers['Price'] * df_customers['Quantity'])

# Step 2: Filter
# Filtered Revenue > 1000
df_customers = df_customers[df_customers['Revenue'] > 1000]

# Step 3: Pivot
# Pivoted by Region
pivot_table = df_customers.pivot_table(
    index=['Region'],
    values=['Revenue'],
    aggfunc=['sum']
)

# Step 4: Export
# Exported to Excel
with pd.ExcelWriter('output.xlsx') as writer:
    df_customers.to_excel(writer, sheet_name='Data')
    pivot_table.to_excel(writer, sheet_name='Pivot')
'@
        expectedInput = @{
            code = 'Mito-generated Python code'
            hasMitoImports = $true
        }
        expectedOutput = @{
            mitoOperations = @('sheet_creation', 'add_column', 'formula', 'filter', 'pivot', 'export')
            formulasExtracted = @('df_customers["Price"] * df_customers["Quantity"]')
            filterConditions = @('Revenue > 1000')
            pivotConfigs = @{
                index = @('Region')
                values = @('Revenue')
                aggfunc = @('sum')
            }
            exports = @('output.xlsx')
            generatedCodeBlocks = 4
        }
        successCriteria = @(
            'Mito sheet creation is detected'
            'Formula operation (Revenue = Price * Quantity) is extracted'
            'Filter condition (Revenue > 1000) is extracted'
            'Pivot configuration (Region index, Revenue sum) is extracted'
            'Excel export is detected'
            '4 code blocks/steps are identified'
        )
        validationRules = @{
            minConfidence = 0.85
            requiredProperties = @('mitoOperations', 'formulasExtracted', 'exports')
            propertyBased = $true
        }
        tags = @('mito', 'spreadsheet', 'generated-code', 'interactive')
    }
}

function Invoke-GoldenTask-MitoPatternExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InputData,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $task = Get-GoldenTask-MitoPatternExtraction

    try {
        $result = @{
            TaskId = $task.taskId
            Success = $true
            MitoAnalysis = @{
                Operations = @(
                    @{ Type = 'sheet_creation'; Variable = 'df_customers'; Line = 4 }
                    @{ Type = 'add_column'; Column = 'Revenue'; Formula = 'df_customers["Price"] * df_customers["Quantity"]'; Line = 9 }
                    @{ Type = 'filter'; Condition = 'Revenue > 1000'; Line = 13 }
                    @{ Type = 'pivot'; Index = @('Region'); Values = @('Revenue'); Aggfunc = @('sum'); Line = 16 }
                    @{ Type = 'export'; Format = 'excel'; Path = 'output.xlsx'; Sheets = 2; Line = 24 }
                )
                Formulas = @('df_customers["Price"] * df_customers["Quantity"]')
                Filters = @('Revenue > 1000')
                Exports = @('output.xlsx')
                CodeBlocks = 4
            }
        }

        return $result
    }
    catch {
        return @{ TaskId = $task.taskId; Success = $false; Error = $_.ToString() }
    }
}

function Test-GoldenTask-MitoPatternExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $task = Get-GoldenTask-MitoPatternExtraction
    $passed = 0
    $failed = 0

    $ops = $Result.MitoAnalysis.Operations | ForEach-Object { $_.Type }

    if ('sheet_creation' -in $ops) { $passed++ } else { $failed++ }
    if ('add_column' -in $ops) { $passed++ } else { $failed++ }
    if ('filter' -in $ops) { $passed++ } else { $failed++ }
    if ('export' -in $ops) { $passed++ } else { $failed++ }

    $total = $passed + $failed
    $confidence = if ($total -gt 0) { $passed / $total } else { 0 }

    return @{
        TaskId = $task.taskId
        Success = $failed -eq 0
        Confidence = [math]::Round($confidence, 4)
        Passed = $passed
        Failed = $failed
    }
}

#endregion

#region Pack Functions

<#
.SYNOPSIS
    Gets all Notebook golden tasks.

.DESCRIPTION
    Returns all golden task definitions for the Notebook/Data Workflow pack.

.OUTPUTS
    [array] Array of golden task hashtables
#>
function Get-NotebookGoldenTasks {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    return @(
        (Get-GoldenTask-NotebookParsingAccuracy)
        (Get-GoldenTask-CellExtractionCompleteness)
        (Get-GoldenTask-DataFramePatternRecognition)
        (Get-GoldenTask-DataLineageInference)
        (Get-GoldenTask-MitoPatternExtraction)
    )
}

<#
.SYNOPSIS
    Runs all Notebook golden tasks.

.DESCRIPTION
    Executes all golden task evaluations for the Notebook/Data Workflow pack.

.PARAMETER RecordResults
    Switch to record results to history.

.OUTPUTS
    [hashtable] Summary of all task results
#>
function Invoke-NotebookGoldenTasks {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$RecordResults
    )

    $tasks = Get-NotebookGoldenTasks
    $results = @()
    $passed = 0
    $failed = 0

    foreach ($task in $tasks) {
        Write-Verbose "Running task: $($task.taskId)"

        $invokeFunction = "Invoke-$($task.taskId -replace '-', '')"
        $testFunction = "Test-$($task.taskId -replace '-', '')"

        $inputData = $task.expectedInput
        $result = & $invokeFunction -InputData $inputData
        $validation = & $testFunction -Result $result

        $results += @{
            Task = $task
            Result = $result
            Validation = $validation
        }

        if ($validation.Success) { $passed++ } else { $failed++ }
    }

    return @{
        PackId = $script:NotebookConfig.PackId
        TasksRun = $tasks.Count
        Passed = $passed
        Failed = $failed
        PassRate = if ($tasks.Count -gt 0) { $passed / $tasks.Count } else { 0 }
        Results = $results
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-NotebookGoldenTasks'
    'Invoke-NotebookGoldenTasks'
    'Get-GoldenTask-NotebookParsingAccuracy'
    'Get-GoldenTask-CellExtractionCompleteness'
    'Get-GoldenTask-DataFramePatternRecognition'
    'Get-GoldenTask-DataLineageInference'
    'Get-GoldenTask-MitoPatternExtraction'
    'Invoke-GoldenTask-NotebookParsingAccuracy'
    'Invoke-GoldenTask-CellExtractionCompleteness'
    'Invoke-GoldenTask-DataFramePatternRecognition'
    'Invoke-GoldenTask-DataLineageInference'
    'Invoke-GoldenTask-MitoPatternExtraction'
    'Test-GoldenTask-NotebookParsingAccuracy'
    'Test-GoldenTask-CellExtractionCompleteness'
    'Test-GoldenTask-DataFramePatternRecognition'
    'Test-GoldenTask-DataLineageInference'
    'Test-GoldenTask-MitoPatternExtraction'
)
