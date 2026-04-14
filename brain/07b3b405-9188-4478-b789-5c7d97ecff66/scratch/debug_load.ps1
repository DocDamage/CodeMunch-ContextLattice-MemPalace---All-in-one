$ModulePath = "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\ingestion"
$ParserPath = Join-Path $ModulePath 'parsers'
@(
    'ExtractionPipeline.ps1',
    'GDScriptParser.ps1',
    'GodotSceneParser.ps1',
    'RPGMakerPluginParser.ps1',
    'BlenderPythonParser.ps1',
    'GeometryNodesParser.ps1',
    'ShaderParser.ps1'
) | ForEach-Object {
    $path = if ($_ -eq 'ExtractionPipeline.ps1') { Join-Path $ModulePath $_ } else { Join-Path $ParserPath $_ }
    Write-Host "Loading $path ..."
    try {
        . $path
        Write-Host "Success"
    } catch {
        Write-Error "Failed: $_"
    }
}
