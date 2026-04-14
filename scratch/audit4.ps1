$rootDir = "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one"
$files = Get-ChildItem -Path $rootDir -Include *.ps1, *.psm1 -Recurse | Where-Object {
    $_.FullName -notmatch "\\(\.git|_agent_swarm_backup|Pester|node_modules|__pycache__)\\" -and $_.FullName -notmatch "\\tests\\"
}

$hardcodedPaths = @{}
$missingOutputType = @{}
$giantFunctions = @{}
$iexUsage = @{}

foreach ($file in $files) {
    if ($file.FullName -match "\\templates\\") { continue }
    $content = Get-Content $file.FullName
    $text = $content -join "`n"
    
    # 1. Hardcoded Absolute Paths (crude heuristic looking for C:\ or Linux root absolute paths inside quotes)
    $paths = ([regex]::Matches($text, '(?i)[''"]([A-Z]:\\[^\n''"]+)[''"]')).Count
    if ($paths -gt 0) {
        $hardcodedPaths[$file.Name] = $paths
    }

    # 2. Invoke-Expression Usage
    $iexCount = ([regex]::Matches($text, '(?i)\b(?:Invoke-Expression|iex)\b\s+')).Count
    if ($iexCount -gt 0) {
        $iexUsage[$file.Name] = $iexCount
    }

    # 3. Extract block per function to measure length and output type
    $functionBlocks = [regex]::Matches($text, '(?is)function\s+([a-zA-Z]+-[a-zA-Z0-9]+)\s*\{.*?\}')
    
    $noOutputCount = 0
    
    foreach ($match in $functionBlocks) {
        $funcName = $match.Groups[1].Value
        $funcBody = $match.Groups[0].Value
        
        # Missing OutputType
        if ($funcBody -notmatch '(?i)\[OutputType\(') {
            $noOutputCount++
        }
        
        # Giant function > 150 lines
        $lineCount = ($funcBody -split "`n").Count
        if ($lineCount -gt 150) {
            $key = "$($file.Name)"
            if (-not $giantFunctions.ContainsKey($key)) { $giantFunctions[$key] = @() }
            $giantFunctions[$key] += "$funcName ($lineCount lines)"
        }
    }
    
    if ($noOutputCount -gt 0) {
        $missingOutputType[$file.Name] = $noOutputCount
    }
}

$output = @()

$output += ""
$output += "=================== MISSING [OutputType()] DECLARATIONS (Top 20) ==================="
$missingOutputType.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value) missing declarations" }

$output += ""
$output += "=================== GIANT FUNCTIONS (>150 Lines) ==================="
$giantFunctions.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | ForEach-Object {
    $funcs = $_.Value -join ", "
    $output += "$($_.Name): $($_.Value.Count) giant functions -> $funcs"
}

$output += ""
$output += "=================== HARDCODED ABSOLUTE PATHS (Heuristic) ==================="
$hardcodedPaths.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value) instances" }

$output += ""
$output += "=================== INVOKE-EXPRESSION ABUSE (Security Risk) ==================="
if ($iexUsage.Count -gt 0) {
    $iexUsage.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { $output += "$($_.Name): $($_.Value) calls" }
} else {
    $output += "None found! Good job."
}

$output | Out-File "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\deep_audit_results.txt" -Append -Encoding UTF8
