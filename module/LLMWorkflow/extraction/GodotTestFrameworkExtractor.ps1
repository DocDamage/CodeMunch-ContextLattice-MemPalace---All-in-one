#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Test Framework (GUT) extractor for LLM Workflow.

.DESCRIPTION
    Extracts structured test data from GUT (Godot Unit Testing) framework files.
    Parses test scripts to extract test cases, assertions, test suites, and mocking patterns.
    Supports both Godot 3 and Godot 4 GUT syntax.

.NOTES
    File Name      : GodotTestFrameworkExtractor.ps1
    Author         : LLM Workflow
    Version        : 1.0.0
    Godot Versions : 3.x, 4.x (GUT 7.x, 8.x, 9.x)
#>

Set-StrictMode -Version Latest

# ============================================================================
# Regex Patterns for GUT Parsing
# ============================================================================

$script:GUTPatterns = @{
    # Test class patterns
    ExtendsGutTest = 'extends\s+(?:res\:\/[^"'']*GutTest|GutTest)'
    TestClassName = '^\s*class_name\s+(?<name>\w+)'
    
    # Test method patterns
    TestMethod = '^\s*func\s+(?<name>test_\w+)\s*\('
    PendingMethod = '^\s*func\s+(?<name>ptest_\w+)\s*\('
    
    # Lifecycle hooks
    BeforeAll = '^\s*func\s+before_all\s*\('
    AfterAll = '^\s*func\s+after_all\s*\('
    BeforeEach = '^\s*func\s+before_each\s*\('
    AfterEach = '^\s*func\s+after_each\s*\('
    
    # Assertion patterns
    AssertTrue = '(?<indent>\s*)assert_true\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertFalse = '(?<indent>\s*)assert_false\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertEq = '(?<indent>\s*)assert_eq\s*\(\s*(?<expected>[^,]+),\s*(?<got>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertNe = '(?<indent>\s*)assert_ne\s*\(\s*(?<expected>[^,]+),\s*(?<got>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertNull = '(?<indent>\s*)assert_null\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertNotNull = '(?<indent>\s*)assert_not_null\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertGt = '(?<indent>\s*)assert_gt\s*\(\s*(?<a>[^,]+),\s*(?<b>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertLt = '(?<indent>\s*)assert_lt\s*\(\s*(?<a>[^,]+),\s*(?<b>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertBetween = '(?<indent>\s*)assert_between\s*\(\s*(?<val>[^,]+),\s*(?<low>[^,]+),\s*(?<high>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertAlmostEq = '(?<indent>\s*)assert_almost_eq\s*\(\s*(?<expected>[^,]+),\s*(?<got>[^,]+),\s*(?<epsilon>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertFileExists = '(?<indent>\s*)assert_file_exists\s*\(\s*["''](?<path>[^"'']*)["'']\s*\)'
    AssertFileDoesNotExist = '(?<indent>\s*)assert_file_does_not_exist\s*\(\s*["''](?<path>[^"'']*)["'']\s*\)'
    AssertIs = '(?<indent>\s*)assert_is\s*\(\s*(?<obj>[^,]+),\s*(?<type>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertStringContains = '(?<indent>\s*)assert_string_contains\s*\(\s*(?<substr>[^,]+),\s*(?<str>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    
    # Mocking and doubling patterns
    Double = '(?<indent>\s*)double\s*\(\s*(?<target>[^)]+)\s*\)'
    PartialDouble = '(?<indent>\s*)partial_double\s*\(\s*(?<target>[^)]+)\s*\)'
    Stub = '(?<indent>\s*)stub\s*\(\s*(?<double>[^,]+),\s*["''](?<method>\w+)["'']\s*\)'
    StubReturnValue = '\.to_return\s*\(\s*(?<val>[^)]+)\s*\)'
    StubReturnSelf = '\.to_do_nothing\s*\(\s*\)'
    Simulate = '(?<indent>\s*)simulate\s*\(\s*(?<obj>[^,]+),\s*(?<delta>[^,]+)(?:,\s*(?<times>[^)]+))?\s*\)'
    
    # Gut configuration
    GutConfigLoad = 'load\s*\(\s*["''](?<path>[^"'']*gut_config\.json)["'']\s*\)'
    GutPath = '(?:gut|GUT)'
    
    # Parameterized tests
    TestWithParams = '(?<indent>\s*)test_with_params\s*\(\s*["''](?<name>\w+)["'']\s*,\s*(?<params>\[.*\])\s*\)'
    
    # Yield/await patterns (async tests)
    YieldToSignal = '(?<indent>\s*)(?:yield|await)\s*\(\s*(?<obj>[^,]+),\s*["''](?<signal>\w+)["'']\s*\)'
    YieldForSeconds = '(?<indent>\s*)(?:yield|await)\s*\(\s*[^,]+\.create_timer\s*\(\s*(?<seconds>[^)]+)\s*\)'
    
    # Spying patterns
    SpyOn = '(?<indent>\s*)spy_on\s*\(\s*(?<obj>[^)]+)\s*\)'
    AssertCalled = '(?<indent>\s*)assert_called\s*\(\s*(?<obj>[^,]+),\s*["''](?<method>\w+)["'']\s*(?:,\s*(?<params>[^)]+))?\s*\)'
    AssertNotCalled = '(?<indent>\s*)assert_not_called\s*\(\s*(?<obj>[^,]+),\s*["''](?<method>\w+)["'']\s*\)'
    AssertCallCount = '(?<indent>\s*)assert_call_count\s*\(\s*(?<obj>[^,]+),\s*["''](?<method>\w+)["''],\s*(?<count>\d+)\s*\)'
    
    # Signal testing
    AssertSignalEmitted = '(?<indent>\s*)assert_signal_emitted\s*\(\s*(?<obj>[^,]+),\s*["''](?<signal>\w+)["'']\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertSignalNotEmitted = '(?<indent>\s*)assert_signal_not_emitted\s*\(\s*(?<obj>[^,]+),\s*["''](?<signal>\w+)["'']\s*\)'
    WatchSignals = '(?<indent>\s*)watch_signals\s*\(\s*(?<obj>[^)]+)\s*\)'
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts GUT test cases from GDScript test files.

.DESCRIPTION
    Parses GUT test scripts and extracts test functions, including
    their assertions, lifecycle hooks, and metadata.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Array. Array of test case objects with name, line, assertions, etc.

.EXAMPLE
    $testCases = Get-GUTTestCases -Path "res://tests/test_player.gd"
#>
function Get-GUTTestCases {
    [CmdletBinding()]
    [OutputType([array])]
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
                Write-Warning "File not found: $Path"
                return @()
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @()
        }
        
        $testCases = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentTest = $null
        $inTestMethod = $false
        $braceDepth = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Check for test method start
            if ($trimmed -match $script:GUTPatterns.TestMethod) {
                $testName = $matches['name']
                $currentTest = @{
                    name = $testName
                    lineNumber = $lineNumber
                    type = 'test'
                    assertions = @()
                    hasSetup = $false
                    hasTeardown = $false
                    usesDoubles = $false
                    usesSpies = $false
                    usesSignals = $false
                    isAsync = $false
                }
                $inTestMethod = $true
                $braceDepth = 0
            }
            elseif ($trimmed -match $script:GUTPatterns.PendingMethod) {
                $testName = $matches['name']
                $currentTest = @{
                    name = $testName
                    lineNumber = $lineNumber
                    type = 'pending'
                    assertions = @()
                    hasSetup = $false
                    hasTeardown = $false
                    usesDoubles = $false
                    usesSpies = $false
                    usesSignals = $false
                    isAsync = $false
                }
                $inTestMethod = $true
                $braceDepth = 0
            }
            elseif ($inTestMethod -and $currentTest) {
                # Track brace depth to detect method end
                $braceDepth += ($line -crep '[^{]').Length - ($line -crep '[^}]').Length
                
                if ($braceDepth -lt 0 -or ($trimmed -eq '}' -and $braceDepth -le 0)) {
                    # End of test method
                    $testCases += $currentTest
                    $currentTest = $null
                    $inTestMethod = $false
                    $braceDepth = 0
                    continue
                }
                
                # Extract assertions
                $assertions = Get-GUTAssertionsFromLine -Line $line -LineNumber $lineNumber
                if ($assertions) {
                    $currentTest.assertions += $assertions
                }
                
                # Check for doubles
                if ($line -match $script:GUTPatterns.Double -or 
                    $line -match $script:GUTPatterns.PartialDouble -or
                    $line -match $script:GUTPatterns.Stub) {
                    $currentTest.usesDoubles = $true
                }
                
                # Check for spies
                if ($line -match $script:GUTPatterns.SpyOn -or
                    $line -match $script:GUTPatterns.AssertCalled -or
                    $line -match $script:GUTPatterns.AssertNotCalled) {
                    $currentTest.usesSpies = $true
                }
                
                # Check for signals
                if ($line -match $script:GUTPatterns.AssertSignalEmitted -or
                    $line -match $script:GUTPatterns.WatchSignals) {
                    $currentTest.usesSignals = $true
                }
                
                # Check for async
                if ($line -match $script:GUTPatterns.YieldToSignal -or
                    $line -match $script:GUTPatterns.YieldForSeconds) {
                    $currentTest.isAsync = $true
                }
            }
        }
        
        # Don't forget the last test if file doesn't end with closing brace
        if ($currentTest) {
            $testCases += $currentTest
        }
        
        Write-Verbose "[Get-GUTTestCases] Extracted $($testCases.Count) test cases"
        return ,$testCases
    }
    catch {
        Write-Error "[Get-GUTTestCases] Failed to extract test cases: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Extracts assertions from a single line of GDScript.

.DESCRIPTION
    Parses a line of code and extracts any GUT assertions found.

.PARAMETER Line
    The line of code to parse.

.PARAMETER LineNumber
    The line number for context.

.OUTPUTS
    System.Array. Array of assertion objects.
#>
function Get-GUTAssertionsFromLine {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,
        
        [Parameter(Mandatory = $true)]
        [int]$LineNumber
    )
    
    $assertions = @()
    
    # assert_true
    if ($Line -match $script:GUTPatterns.AssertTrue) {
        $assertions += @{
            type = 'assert_true'
            expression = $matches['expr'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_false
    if ($Line -match $script:GUTPatterns.AssertFalse) {
        $assertions += @{
            type = 'assert_false'
            expression = $matches['expr'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_eq
    if ($Line -match $script:GUTPatterns.AssertEq) {
        $assertions += @{
            type = 'assert_eq'
            expected = $matches['expected'].Trim()
            actual = $matches['got'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_ne
    if ($Line -match $script:GUTPatterns.AssertNe) {
        $assertions += @{
            type = 'assert_ne'
            expected = $matches['expected'].Trim()
            actual = $matches['got'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_null
    if ($Line -match $script:GUTPatterns.AssertNull) {
        $assertions += @{
            type = 'assert_null'
            expression = $matches['expr'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_not_null
    if ($Line -match $script:GUTPatterns.AssertNotNull) {
        $assertions += @{
            type = 'assert_not_null'
            expression = $matches['expr'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_gt
    if ($Line -match $script:GUTPatterns.AssertGt) {
        $assertions += @{
            type = 'assert_gt'
            left = $matches['a'].Trim()
            right = $matches['b'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_lt
    if ($Line -match $script:GUTPatterns.AssertLt) {
        $assertions += @{
            type = 'assert_lt'
            left = $matches['a'].Trim()
            right = $matches['b'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_between
    if ($Line -match $script:GUTPatterns.AssertBetween) {
        $assertions += @{
            type = 'assert_between'
            value = $matches['val'].Trim()
            lower = $matches['low'].Trim()
            upper = $matches['high'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_almost_eq
    if ($Line -match $script:GUTPatterns.AssertAlmostEq) {
        $assertions += @{
            type = 'assert_almost_eq'
            expected = $matches['expected'].Trim()
            actual = $matches['got'].Trim()
            epsilon = $matches['epsilon'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_file_exists
    if ($Line -match $script:GUTPatterns.AssertFileExists) {
        $assertions += @{
            type = 'assert_file_exists'
            path = $matches['path']
            lineNumber = $lineNumber
        }
    }
    
    # assert_file_does_not_exist
    if ($Line -match $script:GUTPatterns.AssertFileDoesNotExist) {
        $assertions += @{
            type = 'assert_file_does_not_exist'
            path = $matches['path']
            lineNumber = $lineNumber
        }
    }
    
    # assert_is
    if ($Line -match $script:GUTPatterns.AssertIs) {
        $assertions += @{
            type = 'assert_is'
            object = $matches['obj'].Trim()
            expectedType = $matches['type'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_string_contains
    if ($Line -match $script:GUTPatterns.AssertStringContains) {
        $assertions += @{
            type = 'assert_string_contains'
            substring = $matches['substr'].Trim()
            string = $matches['str'].Trim()
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_signal_emitted
    if ($Line -match $script:GUTPatterns.AssertSignalEmitted) {
        $assertions += @{
            type = 'assert_signal_emitted'
            object = $matches['obj'].Trim()
            signal = $matches['signal']
            message = $matches['msg']
            lineNumber = $lineNumber
        }
    }
    
    # assert_called
    if ($Line -match $script:GUTPatterns.AssertCalled) {
        $assertions += @{
            type = 'assert_called'
            object = $matches['obj'].Trim()
            method = $matches['method']
            parameters = $matches['params']
            lineNumber = $lineNumber
        }
    }
    
    return ,$assertions
}

<#
.SYNOPSIS
    Extracts test suites (test classes) from GDScript files.

.DESCRIPTION
    Parses GUT test scripts and extracts test class information,
    including lifecycle hooks and metadata.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Test suite object with metadata.

.EXAMPLE
    $suite = Get-GUTTestSuites -Path "res://tests/test_player.gd"
#>
function Get-GUTTestSuites {
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
                Write-Warning "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }
        
        # Check if this is a GUT test file
        if (-not ($Content -match $script:GUTPatterns.ExtendsGutTest)) {
            Write-Verbose "[Get-GUTTestSuites] File does not extend GutTest"
            return $null
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        $suite = @{
            filePath = $Path
            className = ''
            extends = 'GutTest'
            tests = @()
            lifecycle = @{
                hasBeforeAll = $false
                hasAfterAll = $false
                hasBeforeEach = $false
                hasAfterEach = $false
            }
            usesDoubles = $false
            usesSpies = $false
            usesSignals = $false
            usesAsync = $false
            totalAssertions = 0
        }
        
        # Extract class name
        foreach ($line in $lines) {
            if ($line -match $script:GUTPatterns.TestClassName) {
                $suite.className = $matches['name']
                break
            }
        }
        
        # Extract tests
        $suite.tests = Get-GUTTestCases -Content $Content
        $suite.totalAssertions = ($suite.tests | ForEach-Object { $_.assertions.Count } | Measure-Object -Sum).Sum
        
        # Check for lifecycle hooks
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            
            if ($trimmed -match $script:GUTPatterns.BeforeAll) {
                $suite.lifecycle.hasBeforeAll = $true
            }
            if ($trimmed -match $script:GUTPatterns.AfterAll) {
                $suite.lifecycle.hasAfterAll = $true
            }
            if ($trimmed -match $script:GUTPatterns.BeforeEach) {
                $suite.lifecycle.hasBeforeEach = $true
            }
            if ($trimmed -match $script:GUTPatterns.AfterEach) {
                $suite.lifecycle.hasAfterEach = $true
            }
            
            # Check for doubles
            if ($line -match $script:GUTPatterns.Double -or 
                $line -match $script:GUTPatterns.PartialDouble) {
                $suite.usesDoubles = $true
            }
            
            # Check for spies
            if ($line -match $script:GUTPatterns.SpyOn) {
                $suite.usesSpies = $true
            }
            
            # Check for signals
            if ($line -match $script:GUTPatterns.WatchSignals) {
                $suite.usesSignals = $true
            }
            
            # Check for async
            if ($line -match $script:GUTPatterns.YieldToSignal -or
                $line -match $script:GUTPatterns.YieldForSeconds) {
                $suite.usesAsync = $true
            }
        }
        
        return $suite
    }
    catch {
        Write-Error "[Get-GUTTestSuites] Failed to extract test suite: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts mocking patterns from GUT test files.

.DESCRIPTION
    Parses GUT test scripts and extracts mocking/doubling patterns,
    including stub configurations and spy setups.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Mocking patterns object.

.EXAMPLE
    $mocks = Get-GUTMockingPatterns -Path "res://tests/test_player.gd"
#>
function Get-GUTMockingPatterns {
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
                Write-Warning "File not found: $Path"
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }
        
        $patterns = @{
            doubles = @()
            stubs = @()
            spies = @()
            simulations = @()
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Extract doubles
            if ($line -match $script:GUTPatterns.Double) {
                $patterns.doubles += @{
                    type = 'double'
                    target = $matches['target'].Trim()
                    lineNumber = $lineNumber
                }
            }
            
            # Extract partial doubles
            if ($line -match $script:GUTPatterns.PartialDouble) {
                $patterns.doubles += @{
                    type = 'partial_double'
                    target = $matches['target'].Trim()
                    lineNumber = $lineNumber
                }
            }
            
            # Extract stubs
            if ($line -match $script:GUTPatterns.Stub) {
                $stub = @{
                    double = $matches['double'].Trim()
                    method = $matches['method']
                    lineNumber = $lineNumber
                    returnValue = $null
                    returnSelf = $false
                }
                
                # Check for .to_return() on same line
                if ($line -match $script:GUTPatterns.StubReturnValue) {
                    $stub.returnValue = $matches['val'].Trim()
                }
                
                # Check for .to_do_nothing() on same line
                if ($line -match $script:GUTPatterns.StubReturnSelf) {
                    $stub.returnSelf = $true
                }
                
                $patterns.stubs += $stub
            }
            
            # Extract spy_on calls
            if ($line -match $script:GUTPatterns.SpyOn) {
                $patterns.spies += @{
                    type = 'spy_on'
                    target = $matches['obj'].Trim()
                    lineNumber = $lineNumber
                }
            }
            
            # Extract simulate calls
            if ($line -match $script:GUTPatterns.Simulate) {
                $patterns.simulations += @{
                    object = $matches['obj'].Trim()
                    delta = $matches['delta'].Trim()
                    times = if ($matches['times']) { $matches['times'].Trim() } else { '1' }
                    lineNumber = $lineNumber
                }
            }
        }
        
        return $patterns
    }
    catch {
        Write-Error "[Get-GUTMockingPatterns] Failed to extract mocking patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Main entry point for parsing GUT test files.

.DESCRIPTION
    Parses a GUT test file and returns complete structured extraction
    with test suites, cases, assertions, and mocking patterns.

.PARAMETER Path
    Path to the GUT test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Complete extraction result.

.EXAMPLE
    $result = Invoke-GUTExtract -Path "res://tests/test_player.gd"
#>
function Invoke-GUTExtract {
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
                Write-Warning "File not found: $Path"
                return $null
            }
            $filePath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        else {
            $filePath = 'inline'
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $null
        }
        
        # Check if this is a GUT test file
        if (-not ($Content -match $script:GUTPatterns.ExtendsGutTest)) {
            Write-Verbose "[Invoke-GUTExtract] File does not extend GutTest - not a GUT test file"
            return @{
                filePath = $filePath
                isGUTTest = $false
                parsedAt = [DateTime]::UtcNow.ToString("o")
            }
        }
        
        # Extract all components
        $suite = Get-GUTTestSuites -Content $Content
        $mocks = Get-GUTMockingPatterns -Content $Content
        
        $result = @{
            filePath = $filePath
            fileType = 'gut_test'
            isGUTTest = $true
            suite = $suite
            mocking = $mocks
            statistics = @{
                totalTests = $suite.tests.Count
                pendingTests = ($suite.tests | Where-Object { $_.type -eq 'pending' }).Count
                totalAssertions = $suite.totalAssertions
                usesDoubles = $suite.usesDoubles
                usesSpies = $suite.usesSpies
                usesSignals = $suite.usesSignals
                usesAsync = $suite.usesAsync
                doublesCount = $mocks.doubles.Count
                stubsCount = $mocks.stubs.Count
                spiesCount = $mocks.spies.Count
            }
            parsedAt = [DateTime]::UtcNow.ToString("o")
        }
        
        Write-Verbose "[Invoke-GUTExtract] Extraction complete: $($suite.tests.Count) tests, $($suite.totalAssertions) assertions"
        
        return $result
    }
    catch {
        Write-Error "[Invoke-GUTExtract] Failed to extract GUT tests: $_"
        return $null
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

if ($null -ne $MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-GUTTestCases'
        'Get-GUTTestSuites'
        'Get-GUTMockingPatterns'
        'Invoke-GUTExtract'
        'Get-GUTAssertionsFromLine'
    )
}
