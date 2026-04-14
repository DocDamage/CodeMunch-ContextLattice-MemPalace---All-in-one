$files = Get-ChildItem -Path "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow" -Recurse -Include *.ps1
$results = foreach ($f in $files) {
    [pscustomobject]@{
        Lines = (Get-Content $f.FullName).Count
        Name = $f.Name
    }
}
$results | Sort-Object Lines -Descending | Select-Object -First 20 | ForEach-Object {
    Write-Host ("{0,6}  {1}" -f $_.Lines, $_.Name)
}
