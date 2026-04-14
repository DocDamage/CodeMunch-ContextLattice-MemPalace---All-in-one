@REM Local-dev helper: not intended for CI use.
@echo off
powershell -Command "Import-Module '%~dp0..\module\LLMWorkflow\retrieval\RetrievalCache.ps1' -Force 2>$null; $key = Get-RetrievalCacheKey -Query 'test query' -RetrievalProfile 'test-profile'; Write-Host ('Key generated: ' + $key)"
