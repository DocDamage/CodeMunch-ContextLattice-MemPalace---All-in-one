$rootDir = "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one"
$files = Get-ChildItem -Path $rootDir -Include *.ps1, *.psm1 -Recurse | Where-Object {
    $_.FullName -notmatch "\\(\.git|_agent_swarm_backup|Pester|node_modules|__pycache__)\\" -and $_.FullName -notmatch "\\tests\\"
}

$funcCount = @{}
$noCmdletBinding = @{}
$hardcodedSecrets = @{}
$missingSynopsis = @{}
$suppressOutput = @{}

foreach ($file in $files) {
    if ($file.FullName -match "\\templates\\") { continue }
    $content = Get-Content $file.FullName
    $text = $content -join "`n"
    
    # Check total functions
    $functions = [regex]::Matches($text, '(?i)function\s+([a-z]+-[a-z]+)\s*\{?')
    if ($functions.Count -gt 0) {
        $funcCount[$file.Name] = $functions.Count
        
        # Check missing CmdletBinding
        $bindings = [regex]::Matches($text, '(?i)\[CmdletBinding\(')
        $noCbCount = $functions.Count - $bindings.Count
        if ($noCbCount -gt 0) {
            $noCmdletBinding[$file.Name] = $noCbCount
        }
        
        # Check missing Synopsis
        $synopsis = [regex]::Matches($text, '(?i)\.SYNOPSIS')
        $noSynCount = $functions.Count - $synopsis.Count
        if ($noSynCount -gt 0) {
            $missingSynopsis[$file.Name] = $noSynCount
        }
    }
    
    # Check sensitive data (heuristic)
    $secretsCount = ([regex]::Matches($text, '(?i)(api[_-]?key|bearer|password|secret)[\s=]+["''][a-zA-Z0-9_-]{10,}["'']')).Count
    if ($secretsCount -gt 0) {
        $hardcodedSecrets[$file.Name] = $secretsCount
    }
    
    # Check Write-Output/Out-Null abuses, or `$null =`
    $suppressCount = ([regex]::Matches($text, '>\s*\$null|\$null\s*=|\|\s*Out-Null')).Count
    if ($suppressCount -gt 0) {
        $suppressOutput[$file.Name] = $suppressCount
    }
}

$output = @()

$output += ""
$output += "=================== MISSING [CmdletBinding()] (Top 20) ==================="
$noCmdletBinding.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value) missing out of $($funcCount[$_.Name]) functions" }

$output += ""
$output += "=================== MISSING .SYNOPSIS HELP (Top 20) ==================="
$missingSynopsis.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value) missing out of $($funcCount[$_.Name]) functions" }

$output += ""
$output += "=================== HARDCODED SECRETS (HEURISTIC) ==================="
$hardcodedSecrets.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { $output += "$($_.Name): $($_.Value) matches" }

$output += ""
$output += "=================== SILENT OUTPUT SUPPRESSION (`$null = or | Out-Null) (Top 20) ==================="
$suppressOutput.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value) instances" }

$output | Out-File "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\deep_audit_results.txt" -Append -Encoding UTF8
