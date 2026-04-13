@echo off
powershell -Command "Import-Module 'C:\Users\Doc\Desktop\Projects\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\retrieval\RetrievalCache.ps1' -Force 2>$null; $key = Get-RetrievalCacheKey -Query 'test query' -RetrievalProfile 'test-profile'; Write-Host ('Key generated: ' + $key)"
