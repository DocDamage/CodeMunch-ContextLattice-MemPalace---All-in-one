<#
.SYNOPSIS
    Helper functions for the Golden Task governance system.

.DESCRIPTION
    Contains validation, extraction, and reporting helpers used by the
    core golden task engine.
#>

function Invoke-LLMQuery {
    param(
        [string]$Query,
        [string]$Provider = "default",
        [int]$Timeout = 120
    )

    # Placeholder implementation
    # In production, this would:
    # 1. Call the actual LLM provider (OpenAI, Anthropic, etc.)
    # 2. Apply context from available packs
    # 3. Return structured response

    Write-Verbose "[SIMULATION] Querying LLM provider '$Provider' with timeout $Timeout`s"
    Write-Verbose "[SIMULATION] Query: $Query"

    return @{
        content = "[Simulated LLM Response] This is a placeholder response."
        provider = $Provider
        tokens = @{ prompt = 100; completion = 200 }
        latency = 500
    }
}

function Extract-ResponseProperties {
    param(
        [hashtable]$Response,
        [hashtable]$Task
    )

    $properties = @{}
    $content = $Response.content

    # Analyze based on task category
    switch ($Task.category) {
        'codegen' {
            # Check for various code patterns
            $properties['hasJSDocHeader'] = $content -match '/\*\*[\s\S]*?\*/'
            $properties['hasPluginCommandRegistration'] = $content -match 'PluginManager\.(registerCommand|commands)'
            
            $taskExp = $Task.expectedResult
            $properties['containsCommand'] = if ($taskExp.ContainsKey('containsCommand') -and $taskExp.containsCommand) { $content -match [regex]::Escape($taskExp.containsCommand) } else { $false }
            $properties['containsParameter'] = if ($taskExp.ContainsKey('containsParameter') -and $taskExp.containsParameter) { $content -match [regex]::Escape($taskExp.containsParameter) } else { $false }
            
            $properties['usesGDScriptSyntax'] = $content -match '(extends\s+\w+|func\s+\w+|var\s+\w+|@onready|@export)'
            $properties['hasBlIdname'] = $content -match "bl_idname\s*=\s*['`"']"
            $properties['hasBlLabel'] = $content -match "bl_label\s*=\s*['`"']"
            $properties['hasExecuteMethod'] = $content -match 'def\s+execute\s*\('
            $properties['includesRegistration'] = $content -match '(bpy\.utils\.register_class|register\s*\()'
            $properties['hasClassName'] = if ($taskExp.ContainsKey('hasClassName') -and $taskExp.hasClassName) { 
                $content -match "class_name\s+$($taskExp.hasClassName)" 
            } else { $false }
            $properties['extendsCharacterBody2D'] = $content -match 'extends\s+CharacterBody2D'
            $properties['hasSpeedProperty'] = $content -match '(export|@export).*speed|var\s+speed'
            $properties['hasPhysicsProcess'] = $content -match '_physics_process'
            $properties['createsGameManager'] = $content -match 'class.*GameManager|GameManager'
            $properties['showsConnectMethod'] = $content -match '\.connect\s*\('
            $properties['showsOnreadyPattern'] = $content -match '@onready'
            $properties['extendsNode2D'] = $content -match 'extends\s+Node2D'
            $properties['implementsDraw'] = $content -match '_draw\s*\('
            $properties['usesToolAnnotation'] = $content -match '@tool'
            $properties['extendsEditorPlugin'] = $content -match 'extends\s+EditorPlugin'
            $properties['hasEnterMethod'] = $content -match '_enter_tree'
            $properties['addsDockPanel'] = $content -match 'add_control_to_dock|make_visible'
            $properties['shaderTypeCanvasItem'] = $content -match 'shader_type\s+canvas_item'
            $properties['usesTimeUniform'] = $content -match 'uniform.*TIME|TIME'
            $properties['extendsPropertyGroup'] = $content -match 'extends\s+PropertyGroup'
            $properties['extendsPanel'] = $content -match 'extends\s+Panel'
            $properties['includesDrawMethod'] = $content -match 'def\s+draw\s*\('
            $properties['extendsOperator'] = $content -match 'extends\s+Operator'
            $properties['enablesUseNodes'] = $content -match 'use_nodes\s*=\s*True'
            $properties['createsPrincipledBSDF'] = $content -match 'Principled BSDF|ShaderNodeBsdfPrincipled'
            $properties['linksNodes'] = $content -match 'links\.new'
        }
        'diagnosis' {
            $properties['analyzesConflict'] = $content -match '(conflict|overlap|incompatible|compatible)'
            $properties['citesMethods'] = $content -match '(\.\w+\s*\(|function\s+\w+|def\s+\w+)'
            $properties['providesResolution'] = $content -match '(solution|workaround|fix|recommend|place.*above|place.*below)'
            $properties['mentionsLoadOrder'] = $content -match '(load.*order|order.*load|placement)'
        }
        'extraction' {
            $properties['extractsNotetags'] = $content -match '(notetag|meta|@type)'
            $properties['categorizesByType'] = $content -match '(actor|item|skill|class|weapon|armor|enemy|state)'
            $properties['providesExamples'] = $content -match '(example|e\.g\.|for instance|such as)'
            $pattern = [regex]::Escape('^ <') + '|' + '<.*?>' + '|' + '\w' + '|' + '\d' + '|' + '\[.+?\]'
            $properties['hasValidRegexPatterns'] = $content -match $pattern
        }
        'analysis' {
            $properties['identifiesMethodChain'] = $content -match '(prototype\.|__proto__|method.*chain|call.*chain)'
            $properties['explainsPatchMechanism'] = $content -match '(alias|override|wrap|patch|replace)'
            $properties['mentionsAliasPattern'] = $content -match '(alias|_alias|_\w+_\w+_alias)'
            $properties['showsOriginalVsPatched'] = $content -match '(original|before|after|vs|versus|compared)'
            $properties['identifiesAliases'] = $content -match '(alias|command.*alias|registerCommand)'
            $properties['explainsRegisterCommand'] = $content -match 'registerCommand|PluginManager'
            $properties['explainsSceneInheritance'] = $content -match '(inheritance|inherited scene|scene.*inherit)'
            $properties['showsBaseScene'] = $content -match 'base.*scene|parent.*scene'
            $properties['showsInheritedScene'] = $content -match 'inherited.*scene|child.*scene'
        }
        default {
            # Generic property extraction based on expected result keys
            foreach ($key in $Task.expectedResult.Keys) {
                $properties[$key] = $content -match [regex]::Escape($key)
            }
        }
    }

    # Fallback/Merge: Ensure all expected result keys are present in extracted properties
    if ($Task.expectedResult) {
        foreach ($key in $Task.expectedResult.Keys) {
            if (-not $properties.ContainsKey($key)) {
                # If the expected value is a boolean $true, we just check for presence of the key in content
                # Otherwise we try to match the expected value itself
                $expectedVal = $Task.expectedResult[$key]
                if ($expectedVal -is [string]) {
                    $properties[$key] = $content -match [regex]::Escape($expectedVal)
                } else {
                    $properties[$key] = $content -match [regex]::Escape($key)
                }
            }
        }
    }

    return $properties
}

function Test-PropertyBasedExpectation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Expected,

        [Parameter(Mandatory = $true)]
        [hashtable]$Actual
    )

    begin {
        Write-Verbose "Starting property-based validation"
        $passedProperties = @()
        $failedProperties = @()
        $confidenceSum = 0.0
        $totalProperties = $Expected.Keys.Count
    }

    process {
        if ($totalProperties -eq 0) {
            Write-Warning "No expected properties to validate"
            return @{
                Success = $true
                PassedProperties = @()
                FailedProperties = @()
                Confidence = 1.0
                Details = @{}
            }
        }

        $details = @{}

        foreach ($propertyName in $Expected.Keys) {
            $expectedValue = $Expected[$propertyName]
            $actualValue = $Actual[$propertyName]
            $propertyMatch = $false
            $matchDetails = @{}

            try {
                # Handle different types of expected values
                if ($expectedValue -is [type]) {
                    # Type checking
                    $propertyMatch = $actualValue -is $expectedValue
                    $matchDetails = @{ type = $expectedValue.Name; actualType = $actualValue.GetType().Name }
                }
                elseif ($expectedValue -is [scriptblock]) {
                    # Script block validation
                    $propertyMatch = & $expectedValue $actualValue
                    $matchDetails = @{ validator = 'scriptblock' }
                }
                elseif ($expectedValue -is [hashtable] -and ($expectedValue.ContainsKey('min') -or $expectedValue.ContainsKey('max'))) {
                    # Range checking
                    $min = $expectedValue['min']
                    $max = $expectedValue['max']
                    $propertyMatch = $true
                    if ($null -ne $min -and $actualValue -lt $min) { $propertyMatch = $false }
                    if ($null -ne $max -and $actualValue -gt $max) { $propertyMatch = $false }
                    $matchDetails = @{ min = $min; max = $max; actual = $actualValue }
                }
                elseif ($expectedValue -is [array] -and $expectedValue.Count -gt 0) {
                    # Collection containment - actual should contain all expected items
                    $propertyMatch = $true
                    $missing = @()
                    foreach ($item in $expectedValue) {
                        if ($actualValue -notcontains $item) {
                            $propertyMatch = $false
                            $missing += $item
                        }
                    }
                    $matchDetails = @{ expectedItems = $expectedValue; missingItems = $missing }
                }
                elseif ($expectedValue -is [string] -and $expectedValue.StartsWith('regex:')) {
                    # Regex pattern matching
                    $pattern = $expectedValue.Substring(6)
                    $propertyMatch = $actualValue -match $pattern
                    $matchDetails = @{ pattern = $pattern }
                }
                elseif ($expectedValue -is [string] -and $expectedValue.StartsWith('like:')) {
                    # Wildcard matching
                    $pattern = $expectedValue.Substring(5)
                    $propertyMatch = $actualValue -like $pattern
                    $matchDetails = @{ pattern = $pattern }
                }
                elseif ($expectedValue -eq $true) {
                    # Presence checking - property must exist and not be null/empty
                    $exists = if ($Actual -is [hashtable]) { $Actual.ContainsKey($propertyName) } else { $null -ne $Actual.$propertyName }
                    $count = 1
                    try { if ($null -ne $actualValue) { $count = @($actualValue).Count } } catch { $count = 1 }
                    $propertyMatch = ($exists -and $null -ne $actualValue -and $actualValue -ne '' -and $count -ne 0)
                    $matchDetails = @{ check = 'presence'; exists = $exists; value = $actualValue; count = $count }
                }
                elseif ($expectedValue -eq $false) {
                    # Absence checking - property should not exist, or be null/empty/false
                    $exists = if ($Actual -is [hashtable]) { $Actual.ContainsKey($propertyName) } else { $null -ne $Actual.$propertyName }
                    $count = 0
                    try { if ($null -ne $actualValue) { $count = @($actualValue).Count } } catch { $count = 0 }
                    $propertyMatch = (-not $exists -or $null -eq $actualValue -or $actualValue -eq '' -or $actualValue -eq $false -or $count -eq 0)
                    $matchDetails = @{ check = 'absence'; exists = $exists; value = $actualValue; count = $count }
                }
                else {
                    # Exact value matching (case-insensitive for strings)
                    if ($expectedValue -is [string] -and $actualValue -is [string]) {
                        $propertyMatch = $expectedValue -eq $actualValue
                    }
                    else {
                        $propertyMatch = $expectedValue -eq $actualValue
                    }
                    $matchDetails = @{ expected = $expectedValue; actual = $actualValue }
                }
            }
            catch {
                Write-Verbose "Error validating property '$propertyName': $_"
                $propertyMatch = $false
                $matchDetails = @{ error = $_.ToString() }
            }

            $details[$propertyName] = @{
                Expected = $expectedValue
                Actual = $actualValue
                Match = $propertyMatch
                Details = $matchDetails
            }

            if ($propertyMatch) {
                $passedProperties += $propertyName
                $confidenceSum += 1.0
            }
            else {
                $failedProperties += $propertyName
            }
        }

        $overallConfidence = if ($totalProperties -gt 0) { $confidenceSum / $totalProperties } else { 0 }
        $success = $failedProperties.Count -eq 0

        # Add failed properties to details with a clear flag
        return @{
            Success = $success
            PassedProperties = $passedProperties
            FailedProperties = $failedProperties
            Confidence = [math]::Round($overallConfidence, 4)
            Details = $details
        }
    }
}

function ConvertTo-GoldenTaskHtmlReport {
    param([hashtable]$Report)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$($Report.ReportMetadata.Title)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #333; }
        .summary { background: #f5f5f5; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .metric { display: inline-block; margin: 10px 20px; }
        .metric-value { font-size: 24px; font-weight: bold; }
        .metric-label { font-size: 12px; color: #666; }
        .passed { color: green; }
        .failed { color: red; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #333; color: white; }
    </style>
</head>
<body>
    <h1>$($Report.ReportMetadata.Title)</h1>
    <p>Generated: $($Report.ReportMetadata.GeneratedAt)</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="metric">
            <div class="metric-value">$($Report.Summary.TotalTasks)</div>
            <div class="metric-label">Total Tasks</div>
        </div>
        <div class="metric">
            <div class="metric-value passed">$($Report.Summary.PassedTasks)</div>
            <div class="metric-label">Passed</div>
        </div>
        <div class="metric">
            <div class="metric-value failed">$($Report.Summary.FailedTasks)</div>
            <div class="metric-label">Failed</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Report.Summary.Grade)</div>
            <div class="metric-label">Grade</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Report.Summary.PassRate)%</div>
            <div class="metric-label">Pass Rate</div>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

function ConvertTo-GoldenTaskMarkdownReport {
    param([hashtable]$Report)

    $md = @"
# $($Report.ReportMetadata.Title)

**Generated:** $($Report.ReportMetadata.GeneratedAt)

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | $($Report.Summary.TotalTasks) |
| Passed | $($Report.Summary.PassedTasks) |
| Failed | $($Report.Summary.FailedTasks) |
| Pass Rate | $($Report.Summary.PassRate)% |
| Grade | $($Report.Summary.Grade) |
| Avg Confidence | $([math]::Round($Report.Summary.AverageConfidence * 100, 2))% |

## Difficulty Breakdown

"@
    foreach ($diff in $Report.Summary.TaskBreakdown.Keys) {
        $md += "- **$($diff):** $($Report.Summary.TaskBreakdown[$diff])`n"
    }

    return $md
}

function ConvertTo-Hashtable {
    param(
        $InputObject
    )

    if ($InputObject -is [System.Collections.Hashtable]) {
        return $InputObject
    }
    
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable -InputObject $_ })
    }
    
    if ($InputObject -is [pscustomobject] -or $InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $hash
    }
    
    return $InputObject
}
