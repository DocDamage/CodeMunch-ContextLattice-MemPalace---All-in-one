$moduleDir = "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow"
$files = Get-ChildItem -Path $moduleDir -Filter *.ps1 -Recurse

$todos = @{}
$writeHosts = @{}
$globals = @{}
$emptyCatch = @{}
$argsUsage = @{}
$aliasUsage = @{}

foreach ($file in $files) {
    if ($file.FullName -match "\\templates\\") { continue }
    $content = Get-Content $file.FullName
    $text = $content -join "`n"
    
    # Check TODOs
    $todoCount = ($content | Select-String "(?i)TODO|FIXME|HACK").Count
    if ($todoCount -gt 0) { $todos[$file.Name] = $todoCount }
    
    # Check Write-Host
    $whCount = ($content | Select-String "Write-Host").Count
    if ($whCount -gt 0) { $writeHosts[$file.Name] = $whCount }
    
    # Check $global:
    $glCount = ($content | Select-String "`$global:").Count
    if ($glCount -gt 0) { $globals[$file.Name] = $glCount }
    
    # Check empty catch
    $catchCount = ([regex]::Matches($text, 'catch\s*\{\s*\}')).Count
    if ($catchCount -gt 0) { $emptyCatch[$file.Name] = $catchCount }
    
    # Check $args usage inside functions
    $argsCount = ([regex]::Matches($text, '\$args\b')).Count
    if ($argsCount -gt 0) { $argsUsage[$file.Name] = $argsCount }
    
    # Check for alias usage like % (ForEach-Object) or ? (Where-Object)
    $aliasCount = ([regex]::Matches($text, '\|\s*%\s*\{|\|\s*\?\s*\{')).Count
    if ($aliasCount -gt 0) { $aliasUsage[$file.Name] = $aliasCount }
}

$output = @()

$output += ""
$output += "=================== TODO/FIXME/HACK COUNTS (Top 20) ==================="
$todos.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value)" }

$output += ""
$output += "=================== WRITE-HOST USAGE IN MODULES (Top 20) ==================="
$writeHosts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value)" }

$output += ""
$output += "=================== GLOBAL STATE (`$global:) ==================="
$globals.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { $output += "$($_.Name): $($_.Value)" }

$output += ""
$output += "=================== EMPTY CATCH BLOCKS ==================="
$emptyCatch.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { $output += "$($_.Name): $($_.Value)" }

$output += ""
$output += "=================== OVERUSED `$args (Missing explicit parameters) ==================="
$argsUsage.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value)" }

$output += ""
$output += "=================== ALIAS USAGE (% or ?) IN MODULES ==================="
$aliasUsage.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object { $output += "$($_.Name): $($_.Value)" }

$output | Out-File "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\deep_audit_results.txt" -Append -Encoding UTF8
