#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Test Framework (gdUnit4) extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Extracts structured test data from gdUnit4 test framework files.
    Parses test scripts to extract test suites, test cases, fixtures, and assertions.
    Supports both Godot 4 gdUnit4 syntax.
    
    This parser implements Section 25.6 of the canonical architecture for the
    Godot Engine pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Extract-TestSuites: Extract test suite definitions
    - Extract-TestCases: Extract individual test cases
    - Extract-TestFixtures: Extract test fixture/setup patterns
    - Extract-TestAssertions: Extract assertion patterns

.PARAMETER Path
    Path to the GDScript test file (*Test.gd).

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    JSON with test hierarchy, fixtures, assertions,
    and provenance metadata (source file, extraction timestamp, parser version).

.NOTES
    File Name      : GodotTestFrameworkExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : Godot 4.x (gdUnit4)
    Pack           : godot-engine
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'GodotTestFrameworkExtractor'

# gdUnit4 Test Framework patterns
$script:TestPatterns = @{
    # Test class patterns
    ExtendsGdUnitTest = 'extends\s+(?:GdUnitTestSuite|GdUnitTestAdapter|res\:\/[^"'']*GdUnit)'
    ExtendsGutTest = 'extends\s+(?:GutTest|res\:\/[^"'']*GutTest)'
    TestClassName = '^\s*class_name\s+(?<name>\w+)'
    
    # Test method patterns (gdUnit4)
    TestMethod = '^\s*func\s+(?<name>test_\w+)\s*\('
    FTestMethod = '^\s*func\s+(?<name>ftest_\w+)\s*\('
    
    # GUT test method patterns (legacy compatibility)
    GutTestMethod = '^\s*func\s+(?<name>test_\w+)\s*\('
    GutPendingMethod = '^\s*func\s+(?<name>ptest_\w+)\s*\('
    
    # Test annotations (gdUnit4)
    TestAnnotation = '^\s*@TestCase\s*\(' 
    FTestAnnotation = '^\s*@FTestCase\s*\('
    BeforeAnnotation = '^\s*@Before'
    AfterAnnotation = '^\s*@After'
    BeforeClassAnnotation = '^\s*@BeforeClass'
    AfterClassAnnotation = '^\s*@AfterClass'
    
    # Lifecycle hooks (gdUnit4 style)
    Before = '^\s*func\s+before\s*\('
    After = '^\s*func\s+after\s*\('
    BeforeClass = '^\s*func\s+before_class\s*\('
    AfterClass = '^\s*func\s+after_class\s*\('
    
    # GUT lifecycle hooks (legacy)
    GutBeforeAll = '^\s*func\s+before_all\s*\('
    GutAfterAll = '^\s*func\s+after_all\s*\('
    GutBeforeEach = '^\s*func\s+before_each\s*\('
    GutAfterEach = '^\s*func\s+after_each\s*\('
    
    # gdUnit4 assertion patterns
    AssertTrue = '(?<indent>\s*)assert_bool\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.is_true\s*\(\s*\)'
    AssertFalse = '(?<indent>\s*)assert_bool\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.is_false\s*\(\s*\)'
    AssertEq = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<expected>[^,]+)\s*\)\s*\.is_equal\s*\(\s*(?<got>[^)]+)\s*\)'
    AssertNe = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<expected>[^,]+)\s*\)\s*\.is_not_equal\s*\(\s*(?<got>[^)]+)\s*\)'
    AssertNull = '(?<indent>\s*)assert_that\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.is_null\s*\(\s*\)'
    AssertNotNull = '(?<indent>\s*)assert_that\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.is_not_null\s*\(\s*\)'
    AssertGt = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<a>[^,]+)\s*\)\s*\.is_greater\s*\(\s*(?<b>[^)]+)\s*\)'
    AssertLt = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<a>[^,]+)\s*\)\s*\.is_less\s*\(\s*(?<b>[^)]+)\s*\)'
    AssertBetween = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<val>[^,]+)\s*\)\s*\.is_between\s*\(\s*(?<low>[^,]+),\s*(?<high>[^)]+)\s*\)'
    AssertContains = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<container>[^,]+)\s*\)\s*\.contains\s*\(\s*(?<item>[^)]+)\s*\)'
    AssertEmpty = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.is_empty\s*\(\s*\)'
    AssertNotEmpty = '(?<indent>\s*)assert_(?<type>\w+)\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.is_not_empty\s*\(\s*\)'
    AssertFail = '(?<indent>\s*)assert_that\s*\(\s*false\s*\)\s*\.fail\s*\(\s*(?:["''](?<msg>[^"'']*)["''])?\s*\)'
    AssertSuccess = '(?<indent>\s*)await\s+assert_that\s*\(\s*(?<expr>[^)]+)\s*\)\s*\.await_result\s*\(\s*\)'
    
    # GUT assertion patterns (legacy compatibility)
    GutAssertTrue = '(?<indent>\s*)assert_true\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    GutAssertFalse = '(?<indent>\s*)assert_false\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    GutAssertEq = '(?<indent>\s*)assert_eq\s*\(\s*(?<expected>[^,]+),\s*(?<got>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    GutAssertNe = '(?<indent>\s*)assert_ne\s*\(\s*(?<expected>[^,]+),\s*(?<got>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    GutAssertNull = '(?<indent>\s*)assert_null\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    GutAssertNotNull = '(?<indent>\s*)assert_not_null\s*\(\s*(?<expr>[^)]+)\s*(?:,\s*["''](?<msg>[^"'']*)["''])?\s*\)'
    
    # Async/await patterns (gdUnit4)
    AwaitAssert = '(?<indent>\s*)await\s+assert_that\s*\('
    AwaitSignal = '(?<indent>\s*)await\s+await_signal'
    
    # Test data/fuzzing patterns
    TestData = '(?<indent>\s*)\[TestData\s*\((?<data>[^)]+)\)\s*\]'
    FuzzTest = '(?<indent>\s*)\[FuzzTest\s*\(' 
    
    # Mocking patterns (gdUnit4)
    Mock = '(?<indent>\s*)mock\s*\(\s*(?<target>[^)]+)\s*\)'
    Spy = '(?<indent>\s*)spy\s*\(\s*(?<target>[^)]+)\s*\)'
    Verify = '(?<indent>\s*)verify\s*\(\s*(?<target>[^,)]+)\s*,?\s*(?<times>[^)]*)\s*\)'
    
    # Test runner config
    TestSuiteAnnotation = '^\s*@TestSuite\s*\('
    
    # File detection
    IsTestFile = 'test_|_test\.gd$|Test\.gd$'
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
    Detects if content is a gdUnit4 test file.
.DESCRIPTION
    Analyzes the content to determine if it's a gdUnit4 or GUT test file.
.PARAMETER Content
    The file content to analyze.
.OUTPUTS
    System.String. The detected framework ('gdunit4', 'gut', or 'unknown').
#>
function Get-TestFramework {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Content)
    
    if ($Content -match $script:TestPatterns.ExtendsGdUnitTest) {
        return 'gdunit4'
    }
    if ($Content -match $script:TestPatterns.ExtendsGutTest) {
        return 'gut'
    }
    if ($Content -match $script:TestPatterns.TestAnnotation) {
        return 'gdunit4'
    }
    return 'unknown'
}

# ============================================================================
# Public API Functions - Required by Canonical Document Section 25.6
# ============================================================================

<#
.SYNOPSIS
    Extracts test suite definitions from Godot test files.

.DESCRIPTION
    Parses gdUnit4 or GUT test scripts and extracts test suite (class) information,
    including lifecycle hooks, metadata, and test framework detection.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - suite: Test suite definition object
    - framework: Detected test framework ('gdunit4' or 'gut')
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $suite = Extract-TestSuites -Path "res://tests/PlayerTest.gd"
    
    $suite = Extract-TestSuites -Content $gdscriptContent
#>
function Extract-TestSuites {
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
                    suite = $null
                    framework = 'unknown'
                    isTestFile = $false
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ testCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                suite = $null
                framework = 'unknown'
                isTestFile = $false
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ testCount = 0 }
            }
        }
        
        # Detect test framework
        $framework = Get-TestFramework -Content $Content
        $isTestFile = $framework -ne 'unknown'
        
        if (-not $isTestFile) {
            return @{
                suite = $null
                framework = 'unknown'
                isTestFile = $false
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
                statistics = @{ testCount = 0 }
            }
        }
        
        $lines = $Content -split "`r?`n"
        
        $suite = @{
            filePath = $sourceFile
            className = ''
            extends = if ($framework -eq 'gdunit4') { 'GdUnitTestSuite' } else { 'GutTest' }
            framework = $framework
            tests = @()
            lifecycle = @{
                hasBefore = $false
                hasAfter = $false
                hasBeforeClass = $false
                hasAfterClass = $false
            }
            usesMocks = $false
            usesSpies = $false
            usesAsync = $false
            totalAssertions = 0
        }
        
        # Extract class name
        foreach ($line in $lines) {
            if ($line -match $script:TestPatterns.TestClassName) {
                $suite.className = $matches['name']
                break
            }
        }
        
        # Extract tests
        $suite.tests = Extract-TestCases -Content $Content
        $suite.totalAssertions = $suite.tests.statistics.totalAssertions
        
        # Check for lifecycle hooks
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            
            if ($framework -eq 'gdunit4') {
                if ($trimmed -match $script:TestPatterns.Before) {
                    $suite.lifecycle.hasBefore = $true
                }
                if ($trimmed -match $script:TestPatterns.After) {
                    $suite.lifecycle.hasAfter = $true
                }
                if ($trimmed -match $script:TestPatterns.BeforeClass) {
                    $suite.lifecycle.hasBeforeClass = $true
                }
                if ($trimmed -match $script:TestPatterns.AfterClass) {
                    $suite.lifecycle.hasAfterClass = $true
                }
                
                # Check for mocks
                if ($line -match $script:TestPatterns.Mock) {
                    $suite.usesMocks = $true
                }
                
                # Check for spies
                if ($line -match $script:TestPatterns.Spy -or $line -match $script:TestPatterns.Verify) {
                    $suite.usesSpies = $true
                }
                
                # Check for async
                if ($line -match $script:TestPatterns.AwaitAssert -or $line -match $script:TestPatterns.AwaitSignal) {
                    $suite.usesAsync = $true
                }
            }
            else {
                # GUT patterns
                if ($trimmed -match $script:TestPatterns.GutBeforeAll) {
                    $suite.lifecycle.hasBeforeClass = $true
                }
                if ($trimmed -match $script:TestPatterns.GutAfterAll) {
                    $suite.lifecycle.hasAfterClass = $true
                }
                if ($trimmed -match $script:TestPatterns.GutBeforeEach) {
                    $suite.lifecycle.hasBefore = $true
                }
                if ($trimmed -match $script:TestPatterns.GutAfterEach) {
                    $suite.lifecycle.hasAfter = $true
                }
            }
        }
        
        return @{
            suite = $suite
            framework = $framework
            isTestFile = $true
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                testCount = $suite.tests.testCases.Count
                totalAssertions = $suite.totalAssertions
                framework = $framework
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract test suites: $_"
        return @{
            suite = $null
            framework = 'unknown'
            isTestFile = $false
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ testCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts test cases from Godot test files.

.DESCRIPTION
    Parses gdUnit4 or GUT test scripts and extracts test functions, including
    their assertions, lifecycle hooks, and metadata.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - testCases: Array of test case objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $tests = Extract-TestCases -Path "res://tests/PlayerTest.gd"
    
    $tests = Extract-TestCases -Content $gdscriptContent
#>
function Extract-TestCases {
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
                    testCases = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ testCount = 0; totalAssertions = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                testCases = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ testCount = 0; totalAssertions = 0 }
            }
        }
        
        # Detect test framework
        $framework = Get-TestFramework -Content $Content
        
        $testCases = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentTest = $null
        $inTestMethod = $false
        $braceDepth = 0
        $inComment = $false
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Track multi-line comments
            if ($trimmed.StartsWith('"""')) {
                $inComment = -not $inComment
                continue
            }
            if ($inComment) {
                continue
            }
            
            # Check for test method start based on framework
            $isTest = $false
            $isFocused = $false
            $isPending = $false
            
            if ($framework -eq 'gdunit4') {
                # Check for @TestCase annotation
                if ($trimmed -match $script:TestPatterns.TestAnnotation) {
                    continue  # Skip annotation line, will catch on next line
                }
                if ($trimmed -match $script:TestPatterns.TestMethod) {
                    $isTest = $true
                    $testName = $matches['name']
                }
                if ($trimmed -match $script:TestPatterns.FTestMethod) {
                    $isTest = $true
                    $isFocused = $true
                    $testName = $matches['name']
                }
            }
            else {
                # GUT patterns
                if ($trimmed -match $script:TestPatterns.GutTestMethod) {
                    $isTest = $true
                    $testName = $matches['name']
                }
                elseif ($trimmed -match $script:TestPatterns.GutPendingMethod) {
                    $isTest = $true
                    $isPending = $true
                    $testName = $matches['name']
                }
            }
            
            if ($isTest) {
                # Finish previous test if exists
                if ($currentTest) {
                    $testCases += $currentTest
                }
                
                $currentTest = @{
                    id = [System.Guid]::NewGuid().ToString()
                    name = $testName
                    lineNumber = $lineNumber
                    type = if ($isPending) { 'pending' } elseif ($isFocused) { 'focused' } else { 'test' }
                    framework = $framework
                    assertions = @()
                    hasSetup = $false
                    hasTeardown = $false
                    usesMocks = $false
                    usesSpies = $false
                    usesAsync = $false
                    isDataDriven = $false
                    dataSet = @()
                }
                $inTestMethod = $true
                $braceDepth = 0
            }
            elseif ($inTestMethod -and $currentTest) {
                # Track brace depth to detect method end
                $braceDepth += ($line -creplace '[^{]').Length - ($line -creplace '[^}]').Length
                
                if ($braceDepth -lt 0 -or ($trimmed -eq '}' -and $braceDepth -le 0)) {
                    # End of test method
                    $testCases += $currentTest
                    $currentTest = $null
                    $inTestMethod = $false
                    $braceDepth = 0
                    continue
                }
                
                # Extract assertions
                $assertions = Extract-TestAssertions -Line $line -LineNumber $lineNumber -Framework $framework
                if ($assertions) {
                    $currentTest.assertions += $assertions
                }
                
                # Check for mocks
                if ($line -match $script:TestPatterns.Mock) {
                    $currentTest.usesMocks = $true
                }
                
                # Check for spies
                if ($line -match $script:TestPatterns.Spy -or $line -match $script:TestPatterns.Verify) {
                    $currentTest.usesSpies = $true
                }
                
                # Check for async
                if ($line -match 'await\s+' -or $line -match $script:TestPatterns.AwaitAssert) {
                    $currentTest.usesAsync = $true
                }
                
                # Check for test data
                if ($line -match $script:TestPatterns.TestData) {
                    $currentTest.isDataDriven = $true
                }
            }
        }
        
        # Don't forget the last test if file doesn't end with closing brace
        if ($currentTest) {
            $testCases += $currentTest
        }
        
        $totalAssertions = ($testCases | ForEach-Object { $_.assertions.Count } | Measure-Object -Sum).Sum
        
        Write-Verbose "[$script:ParserName] Extracted $($testCases.Count) test cases"
        
        return @{
            testCases = $testCases
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                testCount = $testCases.Count
                totalAssertions = $totalAssertions
                pendingCount = ($testCases | Where-Object { $_.type -eq 'pending' }).Count
                focusedCount = ($testCases | Where-Object { $_.type -eq 'focused' }).Count
                dataDrivenCount = ($testCases | Where-Object { $_.isDataDriven }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract test cases: $_"
        return @{
            testCases = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ testCount = 0; totalAssertions = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts test fixture/setup patterns from Godot test files.

.DESCRIPTION
    Parses gdUnit4 or GUT test scripts and extracts test fixtures including
    setup (@Before, before), teardown (@After, after), and class-level fixtures.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - fixtures: Array of fixture objects
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $fixtures = Extract-TestFixtures -Path "res://tests/PlayerTest.gd"
    
    $fixtures = Extract-TestFixtures -Content $gdscriptContent
#>
function Extract-TestFixtures {
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
                    fixtures = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ fixtureCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                fixtures = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ fixtureCount = 0 }
            }
        }
        
        # Detect test framework
        $framework = Get-TestFramework -Content $Content
        
        $fixtures = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            if ($framework -eq 'gdunit4') {
                # Before fixture
                if ($trimmed -match $script:TestPatterns.Before) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'before'
                        type = 'setup'
                        scope = 'method'
                        lineNumber = $lineNumber
                        framework = 'gdunit4'
                        hasAnnotation = ($lines[($lineNumber - 2)..($lineNumber - 1)] | Select-String -Pattern '@Before').Count -gt 0
                    }
                }
                
                # After fixture
                if ($trimmed -match $script:TestPatterns.After) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'after'
                        type = 'teardown'
                        scope = 'method'
                        lineNumber = $lineNumber
                        framework = 'gdunit4'
                        hasAnnotation = ($lines[($lineNumber - 2)..($lineNumber - 1)] | Select-String -Pattern '@After').Count -gt 0
                    }
                }
                
                # BeforeClass fixture
                if ($trimmed -match $script:TestPatterns.BeforeClass) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'before_class'
                        type = 'setup'
                        scope = 'class'
                        lineNumber = $lineNumber
                        framework = 'gdunit4'
                        hasAnnotation = ($lines[($lineNumber - 2)..($lineNumber - 1)] | Select-String -Pattern '@BeforeClass').Count -gt 0
                    }
                }
                
                # AfterClass fixture
                if ($trimmed -match $script:TestPatterns.AfterClass) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'after_class'
                        type = 'teardown'
                        scope = 'class'
                        lineNumber = $lineNumber
                        framework = 'gdunit4'
                        hasAnnotation = ($lines[($lineNumber - 2)..($lineNumber - 1)] | Select-String -Pattern '@AfterClass').Count -gt 0
                    }
                }
            }
            else {
                # GUT fixtures
                if ($trimmed -match $script:TestPatterns.GutBeforeAll) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'before_all'
                        type = 'setup'
                        scope = 'class'
                        lineNumber = $lineNumber
                        framework = 'gut'
                    }
                }
                if ($trimmed -match $script:TestPatterns.GutAfterAll) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'after_all'
                        type = 'teardown'
                        scope = 'class'
                        lineNumber = $lineNumber
                        framework = 'gut'
                    }
                }
                if ($trimmed -match $script:TestPatterns.GutBeforeEach) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'before_each'
                        type = 'setup'
                        scope = 'method'
                        lineNumber = $lineNumber
                        framework = 'gut'
                    }
                }
                if ($trimmed -match $script:TestPatterns.GutAfterEach) {
                    $fixtures += @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = 'after_each'
                        type = 'teardown'
                        scope = 'method'
                        lineNumber = $lineNumber
                        framework = 'gut'
                    }
                }
            }
        }
        
        return @{
            fixtures = $fixtures
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                fixtureCount = $fixtures.Count
                byScope = @{
                    class = ($fixtures | Where-Object { $_.scope -eq 'class' }).Count
                    method = ($fixtures | Where-Object { $_.scope -eq 'method' }).Count
                }
                byType = @{
                    setup = ($fixtures | Where-Object { $_.type -eq 'setup' }).Count
                    teardown = ($fixtures | Where-Object { $_.type -eq 'teardown' }).Count
                }
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract test fixtures: $_"
        return @{
            fixtures = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ fixtureCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts assertion patterns from test code.

.DESCRIPTION
    Parses a line of test code and extracts any assertions found.
    Supports both gdUnit4 and GUT assertion patterns.

.PARAMETER Line
    The line of code to parse.

.PARAMETER LineNumber
    The line number for context.

.PARAMETER Framework
    The test framework ('gdunit4' or 'gut').

.OUTPUTS
    System.Array. Array of assertion objects.

.EXAMPLE
    $assertions = Extract-TestAssertions -Line $codeLine -LineNumber 42 -Framework 'gdunit4'
#>
function Extract-TestAssertions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,
        
        [Parameter(Mandatory = $true)]
        [int]$LineNumber,
        
        [Parameter()]
        [string]$Framework = 'gdunit4'
    )
    
    $assertions = @()
    
    if ($Framework -eq 'gdunit4') {
        # gdUnit4 fluent assertions
        
        # assert_bool(...).is_true()
        if ($Line -match $script:TestPatterns.AssertTrue) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_true'
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_bool(...).is_false()
        if ($Line -match $script:TestPatterns.AssertFalse) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_false'
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_equal(...)
        if ($Line -match $script:TestPatterns.AssertEq) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_equal'
                dataType = $matches['type']
                expected = $matches['expected'].Trim()
                actual = $matches['got'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_not_equal(...)
        if ($Line -match $script:TestPatterns.AssertNe) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_not_equal'
                dataType = $matches['type']
                expected = $matches['expected'].Trim()
                actual = $matches['got'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_that(...).is_null()
        if ($Line -match $script:TestPatterns.AssertNull) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_null'
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_that(...).is_not_null()
        if ($Line -match $script:TestPatterns.AssertNotNull) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_not_null'
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_greater(...)
        if ($Line -match $script:TestPatterns.AssertGt) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_greater'
                dataType = $matches['type']
                value = $matches['a'].Trim()
                threshold = $matches['b'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_less(...)
        if ($Line -match $script:TestPatterns.AssertLt) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_less'
                dataType = $matches['type']
                value = $matches['a'].Trim()
                threshold = $matches['b'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_between(...)
        if ($Line -match $script:TestPatterns.AssertBetween) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_between'
                dataType = $matches['type']
                value = $matches['val'].Trim()
                lowerBound = $matches['low'].Trim()
                upperBound = $matches['high'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).contains(...)
        if ($Line -match $script:TestPatterns.AssertContains) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_contains'
                dataType = $matches['type']
                container = $matches['container'].Trim()
                item = $matches['item'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_empty()
        if ($Line -match $script:TestPatterns.AssertEmpty) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_empty'
                dataType = $matches['type']
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # assert_*(...).is_not_empty()
        if ($Line -match $script:TestPatterns.AssertNotEmpty) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_not_empty'
                dataType = $matches['type']
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
            }
        }
        
        # await assert_that(...).await_result()
        if ($Line -match $script:TestPatterns.AssertSuccess) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_await_result'
                expression = $matches['expr'].Trim()
                lineNumber = $lineNumber
                framework = 'gdunit4'
                isAsync = $true
            }
        }
    }
    else {
        # GUT assertions (legacy)
        
        # assert_true
        if ($Line -match $script:TestPatterns.GutAssertTrue) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_true'
                expression = $matches['expr'].Trim()
                message = $matches['msg']
                lineNumber = $lineNumber
                framework = 'gut'
            }
        }
        
        # assert_false
        if ($Line -match $script:TestPatterns.GutAssertFalse) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_false'
                expression = $matches['expr'].Trim()
                message = $matches['msg']
                lineNumber = $lineNumber
                framework = 'gut'
            }
        }
        
        # assert_eq
        if ($Line -match $script:TestPatterns.GutAssertEq) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_equal'
                expected = $matches['expected'].Trim()
                actual = $matches['got'].Trim()
                message = $matches['msg']
                lineNumber = $lineNumber
                framework = 'gut'
            }
        }
        
        # assert_ne
        if ($Line -match $script:TestPatterns.GutAssertNe) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_not_equal'
                expected = $matches['expected'].Trim()
                actual = $matches['got'].Trim()
                message = $matches['msg']
                lineNumber = $lineNumber
                framework = 'gut'
            }
        }
        
        # assert_null
        if ($Line -match $script:TestPatterns.GutAssertNull) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_null'
                expression = $matches['expr'].Trim()
                message = $matches['msg']
                lineNumber = $lineNumber
                framework = 'gut'
            }
        }
        
        # assert_not_null
        if ($Line -match $script:TestPatterns.GutAssertNotNull) {
            $assertions += @{
                id = [System.Guid]::NewGuid().ToString()
                type = 'assert_not_null'
                expression = $matches['expr'].Trim()
                message = $matches['msg']
                lineNumber = $lineNumber
                framework = 'gut'
            }
        }
    }
    
    return $assertions
}

# ============================================================================
# Legacy Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for parsing gdUnit4/GUT test files.
    
    DEPRECATED: Use the specific Extract-* functions instead.

.DESCRIPTION
    Legacy entry point that delegates to the canonical extraction functions.
#>
function Invoke-TestExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
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
        $suite = Extract-TestSuites -Content $Content
        $fixtures = Extract-TestFixtures -Content $Content
        
        return @{
            filePath = $sourceFile
            framework = $suite.framework
            isTestFile = $suite.isTestFile
            suite = $suite.suite
            fixtures = $fixtures.fixtures
            statistics = @{
                totalTests = $suite.statistics.testCount
                totalAssertions = $suite.statistics.totalAssertions
                fixtureCount = $fixtures.statistics.fixtureCount
            }
            metadata = $suite.metadata
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract tests: $_"
        return @{
            filePath = $sourceFile
            success = $false
            error = $_.ToString()
        }
    }
}

<#
.SYNOPSIS
    Extracts GUT test cases from GDScript test files.
    
    DEPRECATED: Use Extract-TestCases instead.
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
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Extract-TestCases -Path $Path
    }
    else {
        Extract-TestCases -Content $Content
    }
    
    return $result.testCases
}

<#
.SYNOPSIS
    Extracts GUT test suites from GDScript files.
    
    DEPRECATED: Use Extract-TestSuites instead.
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
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Extract-TestSuites -Path $Path
    }
    else {
        Extract-TestSuites -Content $Content
    }
    
    return $result.suite
}

<#
.SYNOPSIS
    Extracts GUT mocking patterns from test files.
    
    DEPRECATED: Mocking patterns are now included in Extract-TestCases.
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
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return $null
            }
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        $patterns = @{
            mocks = @()
            spies = @()
            verifications = @()
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Extract mocks
            if ($line -match $script:TestPatterns.Mock) {
                $patterns.mocks += @{
                    type = 'mock'
                    target = $matches['target'].Trim()
                    lineNumber = $lineNumber
                }
            }
            
            # Extract spies
            if ($line -match $script:TestPatterns.Spy) {
                $patterns.spies += @{
                    type = 'spy'
                    target = $matches['target'].Trim()
                    lineNumber = $lineNumber
                }
            }
            
            # Extract verifications
            if ($line -match $script:TestPatterns.Verify) {
                $patterns.verifications += @{
                    type = 'verify'
                    target = $matches['target'].Trim()
                    times = $matches['times'].Trim()
                    lineNumber = $lineNumber
                }
            }
        }
        
        return $patterns
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract mocking patterns: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Extracts assertions from a single line of GDScript.
    
    DEPRECATED: Use Extract-TestAssertions instead.
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
    
    return Extract-TestAssertions -Line $Line -LineNumber $LineNumber -Framework 'gut'
}

# ============================================================================
# Public API Functions - Required Export Functions (Section 25.6.1)
# ============================================================================

<#
.SYNOPSIS
    Exports gdUnit4 test suites from Godot test files.

.DESCRIPTION
    Extracts and exports structured test suite data from gdUnit4 test scripts.
    This is a convenience wrapper around Extract-TestSuites that provides
    additional export options and filtering for gdUnit4-specific features.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.PARAMETER IncludeFixtures
    If specified, includes test fixtures in the export.

.PARAMETER IncludeRawContent
    If specified, includes the raw file content in the output.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - testSuite: Test suite definition object
    - fixtures: Test fixtures (if requested)
    - framework: Detected test framework
    - metadata: Provenance metadata
    - metrics: Test suite metrics

.EXAMPLE
    $suite = Export-GdUnit4TestSuite -Path "res://tests/PlayerTest.gd"
    
    $suite = Export-GdUnit4TestSuite -Content $gdscriptContent -IncludeFixtures
#>
function Export-GdUnit4TestSuite {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeFixtures,
        
        [Parameter()]
        [switch]$IncludeRawContent
    )
    
    try {
        $sourceFile = if ($PSCmdlet.ParameterSetName -eq 'Path') { $Path } else { 'inline' }
        
        # Extract test suite
        $suiteResult = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Extract-TestSuites -Path $Path
        } else {
            Extract-TestSuites -Content $Content
        }
        
        if (-not $suiteResult.isTestFile) {
            return @{
                testSuite = $null
                fixtures = @()
                framework = 'unknown'
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Not a recognized test file")
                metrics = @{}
            }
        }
        
        $result = @{
            testSuite = $suiteResult.suite
            framework = $suiteResult.framework
            metadata = $suiteResult.metadata
            metrics = @{
                testCount = $suiteResult.statistics.testCount
                totalAssertions = $suiteResult.statistics.totalAssertions
                hasLifecycleHooks = $suiteResult.suite.lifecycle.hasBefore -or $suiteResult.suite.lifecycle.hasAfter -or 
                                    $suiteResult.suite.lifecycle.hasBeforeClass -or $suiteResult.suite.lifecycle.hasAfterClass
                usesMocks = $suiteResult.suite.usesMocks
                usesSpies = $suiteResult.suite.usesSpies
                usesAsync = $suiteResult.suite.usesAsync
            }
        }
        
        # Include fixtures if requested
        if ($IncludeFixtures) {
            $fixturesResult = if ($PSCmdlet.ParameterSetName -eq 'Path') {
                Extract-TestFixtures -Path $Path
            } else {
                Extract-TestFixtures -Content $Content
            }
            $result.fixtures = $fixturesResult.fixtures
        }
        
        # Include raw content if requested
        if ($IncludeRawContent -and $PSCmdlet.ParameterSetName -eq 'Path') {
            $result.rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } elseif ($IncludeRawContent) {
            $result.rawContent = $Content
        }
        
        return $result
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export test suite: $_"
        return @{
            testSuite = $null
            fixtures = @()
            framework = 'unknown'
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            metrics = @{}
        }
    }
}

<#
.SYNOPSIS
    Exports test cases from Godot test files.

.DESCRIPTION
    Extracts and exports structured test case data from gdUnit4 or GUT test scripts.
    Provides filtering options for specific test types and detailed assertion information.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.PARAMETER IncludeAssertions
    If specified, includes detailed assertion information for each test.

.PARAMETER Filter
    Filter pattern for test names (supports wildcards).

.PARAMETER IncludePending
    If specified, includes pending/skipped tests.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - testCases: Array of test case objects
    - summary: Summary statistics
    - metadata: Provenance metadata

.EXAMPLE
    $tests = Export-TestCases -Path "res://tests/PlayerTest.gd" -IncludeAssertions
    
    $tests = Export-TestCases -Content $gdscriptContent -Filter "test_player_*"
#>
function Export-TestCases {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [switch]$IncludeAssertions,
        
        [Parameter()]
        [string]$Filter = '*',
        
        [Parameter()]
        [switch]$IncludePending
    )
    
    try {
        $sourceFile = if ($PSCmdlet.ParameterSetName -eq 'Path') { $Path } else { 'inline' }
        
        # Extract test cases
        $testResult = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Extract-TestCases -Path $Path
        } else {
            Extract-TestCases -Content $Content
        }
        
        # Filter test cases
        $filteredTests = $testResult.testCases | Where-Object { 
            $_.name -like $Filter -and ($IncludePending -or $_.type -ne 'pending')
        }
        
        # Calculate summary statistics
        $assertionTypes = @{}
        foreach ($test in $filteredTests) {
            foreach ($assertion in $test.assertions) {
                if ($assertionTypes.ContainsKey($assertion.type)) {
                    $assertionTypes[$assertion.type]++
                } else {
                    $assertionTypes[$assertion.type] = 1
                }
            }
        }
        
        $result = @{
            testCases = @($filteredTests)
            summary = @{
                totalTests = $filteredTests.Count
                totalAssertions = ($filteredTests | ForEach-Object { $_.assertions.Count } | Measure-Object -Sum).Sum
                pendingTests = ($filteredTests | Where-Object { $_.type -eq 'pending' }).Count
                focusedTests = ($filteredTests | Where-Object { $_.type -eq 'focused' }).Count
                dataDrivenTests = ($filteredTests | Where-Object { $_.isDataDriven }).Count
                asyncTests = ($filteredTests | Where-Object { $_.usesAsync }).Count
                testsWithMocks = ($filteredTests | Where-Object { $_.usesMocks }).Count
                testsWithSpies = ($filteredTests | Where-Object { $_.usesSpies }).Count
                averageAssertionsPerTest = if ($filteredTests.Count -gt 0) { 
                    [math]::Round((($filteredTests | ForEach-Object { $_.assertions.Count } | Measure-Object -Sum).Sum / $filteredTests.Count), 2)
                } else { 0 }
                assertionTypeDistribution = $assertionTypes
            }
            metadata = $testResult.metadata
        }
        
        # Remove assertions from test cases if not requested
        if (-not $IncludeAssertions) {
            $result.testCases = $result.testCases | ForEach-Object {
                $tc = $_ | Select-Object *
                $tc.assertions = $_.assertions.Count
                $tc
            }
        }
        
        return $result
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export test cases: $_"
        return @{
            testCases = @()
            summary = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Calculates test coverage for GDScript files.

.DESCRIPTION
    Analyzes test files and the source files they test to calculate coverage metrics.
    Matches test methods to source methods and identifies untested code.

.PARAMETER TestPath
    Path to the test file or directory containing test files.

.PARAMETER SourcePath
    Path to the source files being tested.

.PARAMETER Content
    Test content string (alternative to TestPath, requires SourceContent).

.PARAMETER SourceContent
    Source content string (alternative to SourcePath).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - coverage: Coverage statistics
    - untestedMethods: Array of untested source methods
    - testedMethods: Array of tested source methods
    - metadata: Provenance metadata

.EXAMPLE
    $coverage = Get-TestCoverage -TestPath "res://tests/" -SourcePath "res://src/"
    
    $coverage = Get-TestCoverage -Content $testContent -SourceContent $sourceContent
#>
function Get-TestCoverage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$TestPath,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$SourcePath,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$SourceContent
    )
    
    try {
        $sourceFile = if ($PSCmdlet.ParameterSetName -eq 'Path') { $TestPath } else { 'inline' }
        
        # Load test content
        $testContent = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (Test-Path -LiteralPath $TestPath -PathType Container) {
                # Directory mode - gather all test files
                $testFiles = Get-ChildItem -Path $TestPath -Filter "*Test.gd" -Recurse
                $allTests = @()
                foreach ($file in $testFiles) {
                    $allTests += Extract-TestCases -Path $file.FullName
                }
                $allTests
            } else {
                Extract-TestCases -Path $TestPath
            }
        } else {
            Extract-TestCases -Content $Content
        }
        
        # Load source content
        $sourceMethods = @()
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (Test-Path -LiteralPath $SourcePath -PathType Container) {
                $sourceFiles = Get-ChildItem -Path $SourcePath -Filter "*.gd" -Recurse
                foreach ($file in $sourceFiles) {
                    $parsed = Invoke-GDScriptParse -Path $file.FullName
                    $methods = $parsed.elements | Where-Object { $_.elementType -eq 'method' }
                    $sourceMethods += $methods | ForEach-Object { $_.name }
                }
            } else {
                $parsed = Invoke-GDScriptParse -Path $SourcePath
                $methods = $parsed.elements | Where-Object { $_.elementType -eq 'method' }
                $sourceMethods = $methods | ForEach-Object { $_.name }
            }
        } else {
            $parsed = Invoke-GDScriptParse -Content $SourceContent
            $methods = $parsed.elements | Where-Object { $_.elementType -eq 'method' }
            $sourceMethods = $methods | ForEach-Object { $_.name }
        }
        
        # Extract tested method names from test names
        $testedMethods = @()
        $testCases = if ($testContent -is [array]) { 
            $testContent | ForEach-Object { $_.testCases }
        } else { 
            $testContent.testCases 
        }
        
        foreach ($test in $testCases) {
            # Try to match test name to method name
            # Common patterns: test_method_name, testMethodName, test_methodName
            $testName = $test.name -replace '^test_', '' -replace '^ftest_', ''
            $possibleNames = @(
                $testName
                ($testName -replace '_', '')
                ($testName -replace '_(.)', { $_.Groups[1].Value.ToUpper() })
            )
            
            foreach ($name in $possibleNames) {
                if ($sourceMethods -contains $name) {
                    $testedMethods += $name
                    break
                }
            }
        }
        
        $testedMethods = $testedMethods | Select-Object -Unique
        $untestedMethods = $sourceMethods | Where-Object { $testedMethods -notcontains $_ }
        
        # Calculate coverage percentage
        $coveragePercent = if ($sourceMethods.Count -gt 0) {
            [math]::Round(($testedMethods.Count / $sourceMethods.Count) * 100, 2)
        } else { 0 }
        
        return @{
            coverage = @{
                percentage = $coveragePercent
                totalSourceMethods = $sourceMethods.Count
                testedMethodCount = $testedMethods.Count
                untestedMethodCount = $untestedMethods.Count
            }
            untestedMethods = @($untestedMethods)
            testedMethods = @($testedMethods)
            testCount = $testCases.Count
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate test coverage: $_"
        return @{
            coverage = @{
                percentage = 0
                totalSourceMethods = 0
                testedMethodCount = 0
                untestedMethodCount = 0
            }
            untestedMethods = @()
            testedMethods = @()
            testCount = 0
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Parses and exports test execution results.

.DESCRIPTION
    Parses test result files (XML, JSON, or console output) from gdUnit4 test runs
    and exports structured result data including pass/fail status, errors, and timing.

.PARAMETER ResultPath
    Path to the test result file (XML, JSON, or text format).

.PARAMETER Content
    Test result content string (alternative to Path).

.PARAMETER Format
    Format of the test results (Auto, XML, JSON, or Console).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - results: Parsed test results
    - summary: Execution summary
    - failures: Array of failed tests with details
    - metadata: Provenance metadata

.EXAMPLE
    $results = Export-TestResults -ResultPath "res://tests/results/test_results.xml"
    
    $results = Export-TestResults -Content $consoleOutput -Format Console
#>
function Export-TestResults {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$ResultPath,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('Auto', 'XML', 'JSON', 'Console')]
        [string]$Format = 'Auto'
    )
    
    try {
        $sourceFile = if ($PSCmdlet.ParameterSetName -eq 'Path') { $ResultPath } else { 'inline' }
        
        # Load content
        $resultContent = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $ResultPath)) {
                return @{
                    results = @()
                    summary = @{}
                    failures = @()
                    metadata = New-ProvenanceMetadata -SourceFile $ResultPath -Success $false -Errors @("Result file not found: $ResultPath")
                }
            }
            Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8
        } else {
            $Content
        }
        
        # Auto-detect format
        if ($Format -eq 'Auto') {
            if ($resultContent.Trim().StartsWith('<')) {
                $Format = 'XML'
            } elseif ($resultContent.Trim().StartsWith('{') -or $resultContent.Trim().StartsWith('[')) {
                $Format = 'JSON'
            } else {
                $Format = 'Console'
            }
        }
        
        $results = @()
        $failures = @()
        $summary = @{}
        
        switch ($Format) {
            'XML' {
                # Parse JUnit-style XML
                [xml]$xml = $resultContent
                if ($xml.testsuites) {
                    foreach ($suite in $xml.testsuites.testsuite) {
                        foreach ($test in $suite.testcase) {
                            $result = @{
                                name = $test.name
                                classname = $test.classname
                                time = [double]$test.time
                                status = 'passed'
                                error = $null
                                failure = $null
                            }
                            if ($test.failure) {
                                $result.status = 'failed'
                                $result.failure = $test.failure.InnerText
                                $failures += $result
                            }
                            if ($test.error) {
                                $result.status = 'error'
                                $result.error = $test.error.InnerText
                                $failures += $result
                            }
                            if ($test.skipped) {
                                $result.status = 'skipped'
                            }
                            $results += $result
                        }
                    }
                    $summary = @{
                        totalTests = [int]$xml.testsuites.tests
                        failures = [int]$xml.testsuites.failures
                        errors = [int]$xml.testsuites.errors
                        skipped = [int]$xml.testsuites.skipped
                        time = [double]$xml.testsuites.time
                    }
                }
            }
            'JSON' {
                # Parse JSON format
                $json = $resultContent | ConvertFrom-Json
                if ($json.tests) {
                    foreach ($test in $json.tests) {
                        $result = @{
                            name = $test.name
                            status = $test.status
                            time = $test.time
                            error = $test.error
                            failure = $test.failure
                        }
                        if ($test.status -eq 'failed' -or $test.status -eq 'error') {
                            $failures += $result
                        }
                        $results += $result
                    }
                    $summary = @{
                        totalTests = $json.total_tests
                        failures = $json.failures
                        errors = $json.errors
                        skipped = $json.skipped
                        time = $json.total_time
                    }
                }
            }
            'Console' {
                # Parse console output patterns (gdUnit4 style)
                $lines = $resultContent -split "`r?`n"
                $currentTest = $null
                $inFailure = $false
                $failureBuffer = @()
                
                foreach ($line in $lines) {
                    # Match test result patterns
                    if ($line -match '^\s*\[\s*(PASS|FAIL|ERROR|SKIP)\s*\]\s*(\S+)') {
                        if ($currentTest) {
                            if ($failureBuffer.Count -gt 0) {
                                $currentTest.failure = ($failureBuffer -join "`n").Trim()
                            }
                            $results += $currentTest
                        }
                        
                        $currentTest = @{
                            name = $matches[2]
                            status = $matches[1].ToLower()
                            time = 0
                            error = $null
                            failure = $null
                        }
                        
                        if ($currentTest.status -eq 'fail' -or $currentTest.status -eq 'error') {
                            $currentTest.status = if ($currentTest.status -eq 'fail') { 'failed' } else { 'error' }
                            $inFailure = $true
                            $failureBuffer = @()
                        } else {
                            $inFailure = $false
                        }
                    }
                    elseif ($inFailure -and $line -match '^\s+(.*)$') {
                        $failureBuffer += $matches[1]
                    }
                    elseif ($line -match 'Test\s+summary:\s*(\d+)\s+tests?\s*,\s*(\d+)\s+passed\s*,\s*(\d+)\s+failed') {
                        $summary = @{
                            totalTests = [int]$matches[1]
                            passed = [int]$matches[2]
                            failures = [int]$matches[3]
                        }
                    }
                }
                
                # Don't forget the last test
                if ($currentTest) {
                    if ($failureBuffer.Count -gt 0) {
                        $currentTest.failure = ($failureBuffer -join "`n").Trim()
                    }
                    $results += $currentTest
                }
                
                $failures = $results | Where-Object { $_.status -eq 'failed' -or $_.status -eq 'error' }
            }
        }
        
        return @{
            results = $results
            summary = $summary
            failures = @($failures)
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export test results: $_"
        return @{
            results = @()
            summary = @{}
            failures = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Calculates comprehensive test metrics for GDScript test files.

.DESCRIPTION
    Analyzes test files to calculate various metrics including assertions per test,
    test complexity, coverage indicators, and quality metrics.

.PARAMETER Path
    Path to the GDScript test file.

.PARAMETER Content
    GDScript content string (alternative to Path).

.PARAMETER SourcePath
    Optional path to source files for coverage calculation.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - metrics: Comprehensive test metrics
    - quality: Code quality indicators
    - recommendations: Array of improvement recommendations
    - metadata: Provenance metadata

.EXAMPLE
    $metrics = Get-TestMetrics -Path "res://tests/PlayerTest.gd"
    
    $metrics = Get-TestMetrics -Content $testContent -SourcePath "res://src/Player.gd"
#>
function Get-TestMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [string]$SourcePath
    )
    
    try {
        $sourceFile = if ($PSCmdlet.ParameterSetName -eq 'Path') { $Path } else { 'inline' }
        
        # Extract test data
        $testResult = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Export-TestCases -Path $Path -IncludeAssertions
        } else {
            Export-TestCases -Content $Content -IncludeAssertions
        }
        
        $testCases = $testResult.testCases
        
        # Calculate assertion metrics
        $assertionsPerTest = $testCases | ForEach-Object { $_.assertions.Count }
        $avgAssertions = if ($testCases.Count -gt 0) {
            [math]::Round(($assertionsPerTest | Measure-Object -Average).Average, 2)
        } else { 0 }
        $maxAssertions = ($assertionsPerTest | Measure-Object -Maximum).Maximum
        $minAssertions = ($assertionsPerTest | Measure-Object -Minimum).Minimum
        $testsWithNoAssertions = ($assertionsPerTest | Where-Object { $_ -eq 0 }).Count
        $testsWithManyAssertions = ($assertionsPerTest | Where-Object { $_ -gt 10 }).Count
        
        # Calculate assertion type distribution
        $assertionTypes = @{}
        $totalAssertions = 0
        foreach ($test in $testCases) {
            foreach ($assertion in $test.assertions) {
                $totalAssertions++
                if ($assertionTypes.ContainsKey($assertion.type)) {
                    $assertionTypes[$assertion.type]++
                } else {
                    $assertionTypes[$assertion.type] = 1
                }
            }
        }
        
        # Calculate test type distribution
        $testTypes = @{
            standard = ($testCases | Where-Object { $_.type -eq 'test' -and -not $_.isDataDriven -and -not $_.usesAsync }).Count
            focused = ($testCases | Where-Object { $_.type -eq 'focused' }).Count
            pending = ($testCases | Where-Object { $_.type -eq 'pending' }).Count
            async = ($testCases | Where-Object { $_.usesAsync }).Count
            dataDriven = ($testCases | Where-Object { $_.isDataDriven }).Count
            withMocks = ($testCases | Where-Object { $_.usesMocks }).Count
            withSpies = ($testCases | Where-Object { $_.usesSpies }).Count
        }
        
        # Calculate coverage if source path provided
        $coverageMetrics = $null
        if ($SourcePath) {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $coverageMetrics = Get-TestCoverage -TestPath $Path -SourcePath $SourcePath
            } else {
                $sourceContent = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($sourceContent) {
                    $coverageMetrics = Get-TestCoverage -Content $Content -SourceContent $sourceContent
                }
            }
        }
        
        # Generate recommendations
        $recommendations = @()
        
        if ($testsWithNoAssertions -gt 0) {
            $recommendations += @{
                type = 'warning'
                message = "$testsWithNoAssertions test(s) have no assertions. Consider adding assertions or removing empty tests."
                priority = 'high'
            }
        }
        
        if ($testsWithManyAssertions -gt 0) {
            $recommendations += @{
                type = 'suggestion'
                message = "$testsWithManyAssertions test(s) have more than 10 assertions. Consider breaking these into smaller, more focused tests."
                priority = 'medium'
            }
        }
        
        if ($testTypes.pending -gt ($testCases.Count * 0.2)) {
            $recommendations += @{
                type = 'warning'
                message = "More than 20% of tests are pending/skipped. Consider completing or removing these tests."
                priority = 'medium'
            }
        }
        
        if ($avgAssertions -lt 2 -and $testCases.Count -gt 0) {
            $recommendations += @{
                type = 'suggestion'
                message = "Average assertions per test ($avgAssertions) is low. Consider adding more thorough assertions."
                priority = 'low'
            }
        }
        
        if ($coverageMetrics -and $coverageMetrics.coverage.percentage -lt 70) {
            $recommendations += @{
                type = 'warning'
                message = "Code coverage is below 70% ($($coverageMetrics.coverage.percentage)%). Consider adding tests for untested methods."
                priority = 'high'
            }
        }
        
        # Quality score (0-100)
        $qualityScore = 100
        $qualityScore -= ($testsWithNoAssertions * 10)  # -10 per test without assertions
        $qualityScore -= ($testsWithManyAssertions * 5)  # -5 per test with too many assertions
        $qualityScore -= [math]::Min($testTypes.pending * 2, 20)  # -2 per pending test, max 20
        if ($coverageMetrics) {
            $qualityScore = [math]::Min($qualityScore, $coverageMetrics.coverage.percentage)
        }
        $qualityScore = [math]::Max(0, $qualityScore)
        
        return @{
            metrics = @{
                testCount = $testCases.Count
                totalAssertions = $totalAssertions
                assertionsPerTest = @{
                    average = $avgAssertions
                    minimum = $minAssertions
                    maximum = $maxAssertions
                }
                testsWithNoAssertions = $testsWithNoAssertions
                testsWithManyAssertions = $testsWithManyAssertions
                testTypes = $testTypes
                assertionTypes = $assertionTypes
                coverage = if ($coverageMetrics) { $coverageMetrics.coverage } else { $null }
            }
            quality = @{
                score = $qualityScore
                rating = if ($qualityScore -ge 90) { 'A' } elseif ($qualityScore -ge 80) { 'B' } elseif ($qualityScore -ge 70) { 'C' } elseif ($qualityScore -ge 60) { 'D' } else { 'F' }
                indicators = @{
                    hasFocusedTests = $testTypes.focused -gt 0
                    hasPendingTests = $testTypes.pending -gt 0
                    hasAsyncTests = $testTypes.async -gt 0
                    usesMocking = $testTypes.withMocks -gt 0
                    usesSpies = $testTypes.withSpies -gt 0
                }
            }
            recommendations = $recommendations
            metadata = $testResult.metadata
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate test metrics: $_"
        return @{
            metrics = @{}
            quality = @{ score = 0; rating = 'F' }
            recommendations = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

# Public functions exported via module wildcard
