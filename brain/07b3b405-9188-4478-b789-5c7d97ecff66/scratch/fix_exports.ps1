$files = Get-ChildItem -Path "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\ingestion\parsers\*.ps1"
foreach ($f in $files) {
    $content = Get-Content -Path $f.FullName -Raw
    if ($content -match '(?m)^Export-ModuleMember' -and $content -notmatch 'if \(\$MyInvocation\.InvocationName') {
        Write-Host "Fixing $($f.Name)..."
        $newContent = $content -replace '(?m)^Export-ModuleMember', 'if ($MyInvocation.InvocationName -ne ".") { Export-ModuleMember'
        $newContent = $newContent + "`r`n}`r`n"
        $newContent | Set-Content -Path $f.FullName -Encoding UTF8
    }
}
