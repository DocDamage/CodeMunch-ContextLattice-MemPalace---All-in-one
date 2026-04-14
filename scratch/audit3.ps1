$rootDir = "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one"
$files = Get-ChildItem -Path $rootDir -Include *.ps1, *.psm1 -Recurse | Where-Object {
    $_.FullName -notmatch "\\(\.git|_agent_swarm_backup|Pester|node_modules|__pycache__)\\" -and $_.FullName -notmatch "\\tests\\"
}

$approvedVerbs = (Get-Verb).Verb
$unapprovedVerbs = @{}

foreach ($file in $files) {
    if ($file.FullName -match "\\templates\\") { continue }
    $content = Get-Content $file.FullName
    $text = $content -join "`n"
    
    $functions = [regex]::Matches($text, '(?i)function\s+([a-zA-Z]+)-([a-zA-Z0-9]+)')
    foreach ($match in $functions) {
        $verb = $match.Groups[1].Value
        # Check against approved verbs case-insensitively
        $isApproved = $false
        foreach ($v in $approvedVerbs) {
            if ($v -eq $verb) { $isApproved = $true; break }
        }
        
        if (-not $isApproved) {
            $funcName = $match.Groups[1].Value + "-" + $match.Groups[2].Value
            $key = "$($file.Name)"
            if (-not $unapprovedVerbs.ContainsKey($key)) {
                $unapprovedVerbs[$key] = @()
            }
            if ($funcName -notin $unapprovedVerbs[$key]) {
                $unapprovedVerbs[$key] += $funcName
            }
        }
    }
}

$output = @()
$output += ""
$output += "=================== UNAPPROVED POWERSHELL VERBS ==================="
$unapprovedVerbs.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 30 | ForEach-Object {
    $verbs = $_.Value -join ", "
    $output += "$($_.Name): $($_.Value.Count) unapproved ($verbs)"
}

$output | Out-File "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\deep_audit_results.txt" -Append -Encoding UTF8
