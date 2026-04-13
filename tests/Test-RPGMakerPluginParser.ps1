# Test RPGMakerPluginParser module
$ErrorActionPreference = 'Stop'

$testPluginContent = @'
//=============================================================================
// TestPlugin
//=============================================================================
/*:
 * @target MZ
 * @plugindesc Test Plugin for demonstration
 * @author Test Author
 * @url https://example.com/test
 * @version 1.2.3
 *
 * @help
 * This is the help text for the plugin.
 * It can span multiple lines.
 *
 * @param ParamOne
 * @text Parameter One
 * @desc This is the first parameter
 * @type number
 * @default 100
 * @min 0
 * @max 1000
 *
 * @param ParamTwo
 * @text Parameter Two  
 * @desc A string parameter
 * @type string
 * @default hello
 *
 * @param ParamThree
 * @text Parameter Three
 * @desc A boolean parameter
 * @type boolean
 * @default true
 *
 * @command DoSomething
 * @text Do Something
 * @desc Execute something useful
 * @arg target
 * @type actor
 * @default 1
 *
 * @command DoSomethingElse
 * @text Do Something Else
 * @desc Another command
 * @arg amount
 * @type number
 * @default 10
 * @arg message
 * @type string
 * @default "Hello"
 *
 * @pluginCommand legacyCommand arg1 arg2
 *
 * @reqPlugin RequiredPlugin
 * @before PluginToLoadBefore
 * @after PluginToLoadAfter
 * @conflict ConflictingPlugin
 */

(function() {
    'use strict';
    
    const pluginName = 'TestPlugin';
    const parameters = PluginManager.parameters(pluginName);
    
})();
'@

# Load the parser
$modulePath = Join-Path $PSScriptRoot "..\module\LLMWorkflow\extraction\RPGMakerPluginParser.ps1"
Write-Host "Loading from: $modulePath"

$ErrorActionPreference = 'SilentlyContinue'
. $modulePath
$ErrorActionPreference = 'Stop'

Write-Host "`n=== Testing RPGMakerPluginParser ===" -ForegroundColor Cyan

# Test Get-PluginMetadata
$metadata = Get-PluginMetadata -Content $testPluginContent
Write-Host "`nMetadata extraction:" -ForegroundColor Yellow
Write-Host "  Plugin: $($metadata.pluginName)"
Write-Host "  Author: $($metadata.author)"
Write-Host "  Version: $($metadata.version)"
Write-Host "  Target: $($metadata.targetEngine)"
Write-Host "  URL: $($metadata.url)"

if ($metadata.pluginName -eq "Test Plugin for demonstration" -and $metadata.author -eq "Test Author") {
    Write-Host "  [PASS] Metadata extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Metadata extraction issue" -ForegroundColor Red
}

# Test Get-PluginParameters
$params = Get-PluginParameters -Content $testPluginContent
Write-Host "`nParameters extraction (found $($params.Count)):" -ForegroundColor Yellow
foreach ($p in $params) {
    Write-Host "  - $($p.name) ($($p.type)) = $($p.default) | displayName: $($p.displayName)"
}

if ($params.Count -eq 3 -and $params[0].name -eq "ParamOne" -and $params[0].type -eq "number" -and $params[0].min -eq 0 -and $params[0].max -eq 1000) {
    Write-Host "  [PASS] Parameters extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Parameter extraction issue" -ForegroundColor Red
}

# Test Get-PluginCommands
$commands = Get-PluginCommands -Content $testPluginContent
Write-Host "`nCommands extraction (found $($commands.Count)):" -ForegroundColor Yellow
foreach ($c in $commands) {
    Write-Host "  - $($c.name): $($c.displayName)"
    Write-Host "    args: $($c.args.Count)"
    foreach ($a in $c.args) {
        Write-Host "      - $($a.name) ($($a.type)) = $($a.default)"
    }
}

if ($commands.Count -eq 2 -and $commands[0].name -eq "DoSomething" -and $commands[0].args.Count -eq 1) {
    Write-Host "  [PASS] Commands extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Command extraction issue" -ForegroundColor Red
}

# Test Get-PluginLegacyCommands
$legacy = Get-PluginLegacyCommands -Content $testPluginContent
Write-Host "`nLegacy plugin commands (found $($legacy.Count)):" -ForegroundColor Yellow
foreach ($l in $legacy) {
    Write-Host "  - $($l.command) args: $($l.args -join ', ')"
}

if ($legacy.Count -eq 1 -and $legacy[0].command -eq "legacyCommand") {
    Write-Host "  [PASS] Legacy commands extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Legacy command extraction issue" -ForegroundColor Red
}

# Test Get-PluginDependencies
$deps = Get-PluginDependencies -Content $testPluginContent
Write-Host "`nDependencies (found $($deps.Count)):" -ForegroundColor Yellow
foreach ($d in $deps) {
    Write-Host "  - $d"
}

if ($deps -contains "RequiredPlugin") {
    Write-Host "  [PASS] Dependencies extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Dependency extraction issue" -ForegroundColor Red
}

# Test Get-PluginConflicts
$conflicts = Get-PluginConflicts -Content $testPluginContent
Write-Host "`nConflicts (found $($conflicts.Count)):" -ForegroundColor Yellow
foreach ($c in $conflicts) {
    Write-Host "  - $c"
}

if ($conflicts -contains "ConflictingPlugin") {
    Write-Host "  [PASS] Conflicts extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Conflict extraction issue" -ForegroundColor Red
}

# Test Get-PluginOrder
$order = Get-PluginOrder -Content $testPluginContent
Write-Host "`nLoad order:" -ForegroundColor Yellow
Write-Host "  Before: $($order.before -join ', ')"
Write-Host "  After: $($order.after -join ', ')"

if ($order.before -contains "PluginToLoadBefore" -and $order.after -contains "PluginToLoadAfter") {
    Write-Host "  [PASS] Load order extracted correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Load order extraction issue" -ForegroundColor Red
}

# Test full parser
$manifest = Invoke-RPGMakerPluginParse -Content $testPluginContent
Write-Host "`nFull manifest:" -ForegroundColor Yellow
Write-Host "  pluginName: $($manifest.pluginName)"
Write-Host "  author: $($manifest.author)"
Write-Host "  version: $($manifest.version)"
Write-Host "  targetEngine: $($manifest.targetEngine)"
Write-Host "  url: $($manifest.url)"
Write-Host "  parameters: $($manifest.parameters.Count)"
Write-Host "  commands: $($manifest.commands.Count)"
Write-Host "  pluginCommands: $($manifest.pluginCommands.Count)"
Write-Host "  dependencies: $($manifest.dependencies.Count)"
Write-Host "  conflicts: $($manifest.conflicts.Count)"

if ($manifest.pluginName -eq "Test Plugin for demonstration" -and 
    $manifest.parameters.Count -eq 3 -and 
    $manifest.commands.Count -eq 2 -and
    $manifest.targetEngine -eq "MZ") {
    Write-Host "  [PASS] Full parser working correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Full parser issue" -ForegroundColor Red
}

# Test Test-PluginConflict
$otherPlugin = @{
    pluginName = "ConflictingPlugin"
    conflicts = @()
    order = @{ before = @(); after = @() }
}
$conflictResults = Test-PluginConflict -Manifest $manifest -OtherManifests @($otherPlugin)
Write-Host "`nConflict test:" -ForegroundColor Yellow
Write-Host "  Conflicts found: $($conflictResults.Count)"
if ($conflictResults.Count -gt 0) {
    foreach ($cr in $conflictResults) {
        Write-Host "  - $($cr.plugin) ($($cr.conflictType)): $($cr.description)"
    }
}

# Should find at least the explicit conflict
$explicitConflict = $conflictResults | Where-Object { $_.plugin -eq "ConflictingPlugin" -and $_.conflictType -eq "explicit" }
if ($explicitConflict) {
    Write-Host "  [PASS] Conflict detection working correctly" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Conflict detection issue" -ForegroundColor Red
}

# Output full JSON
Write-Host "`nFull JSON Output:" -ForegroundColor Cyan
$manifest | ConvertTo-Json -Depth 10

Write-Host "`n=== All tests complete ===" -ForegroundColor Cyan
