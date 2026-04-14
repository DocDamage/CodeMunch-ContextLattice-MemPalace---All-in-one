$file = "f:\stuff from desktop\CodeMunch-ContextLattice-MemPalace---All-in-one\deep_audit_results.txt"
$origContent = Get-Content -Path $file -Raw 

# 1. Fix Formatting Artifacts (replacing `=$` with `$`)
$content = $origContent -replace '=`\$', '$'

# 2. Add Executive Summary
$execSummary = @"

## Executive Summary
This document provides a holistic diagnostic assessment of technical debt across the CodeMunch/ContextLattice/MemPalace mono-repo. While the platform currently boasts massive capability coverage, it suffers deeply from monolithic script structures, omitted pipeline parameter contracts, silent error swallowing, and incomplete strict mode enforcement. 

Systematically eradicating these classes of structural debt is an essential prerequisite for moving the repository from "functioning prototype" to a secure, stable v1.0 release. The report details Epics aimed at syntactical health, code defensiveness, file decoupling, and API contracts.
"@

# Inject executive summary before the "2. What Needs To Be Done" block
$content = $content -replace "(?s)(## 1\. Project Context & Objectives.*?)(## 2\. What Needs To Be Done)", "`$1$execSummary`n`n`$2"

# 3. Clean up the raw audit dump (remove duplicates, handle empty sections, format markdown, and sort)
# Find where the raw violations begin
$splitMarker = '## 3. Raw Infrastructure Audit Violations'
$partsMain = $content -split $splitMarker
if ($partsMain.Count -gt 1) {
    $headerBlock = $partsMain[0]
    $auditBlock = $partsMain[1]
    
    # Remove the sub-marker text if it exists
    $auditBlock = $auditBlock -replace '\*\(The underlying data.*?\)\*', ''
    
    # Split out the individual sections based on "=================== SECTION NAME ==================="
    $sections = $auditBlock -split "===================\s*(.+?)\s*==================="
    
    $newBody = @()
    # $sections[0] is garbage before the first header
    for ($i = 1; $i -lt $sections.Count; $i += 2) {
        $sectionName = $sections[$i]
        $sectionContent = $sections[$i+1].Trim()
        
        $newBody += ""
        $newBody += "### $sectionName"
        
        if (-not $sectionContent) {
            $newBody += "- *None found!*"
            continue
        }
        
        $lines = $sectionContent -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
        
        # Deduplicate exactly (fixes bootstrap-project.ps1 triplicate)
        $uniqueLines = @()
        $seen = @{}
        foreach ($line in $lines) {
            if (-not $seen[$line.Trim()]) {
                $uniqueLines += $line.Trim()
                $seen[$line.Trim()] = $true
            }
        }
        
        # Smart Sort: Sort by embedded integer descending if found, else alphabetically
        $sortedLines = $uniqueLines | Sort-Object {
            if ($_ -match ':\s*(\d+)') { return -[int]$matches[1] }
            if ($_ -match '\((\d+)\s*lines\)') { return -[int]$matches[1] }
            return $_
        }
        
        # Apply Markdown lists
        foreach ($line in $sortedLines) {
            if ($line -match '^Found ') {
                $newBody += "- *$line*"
            } elseif ($line -match '^\.\.\.and') {
                $newBody += "- *$line*"
            } elseif ($line -notmatch '^-') {
                $newBody += "- $line"
            } else {
                $newBody += $line
            }
        }
    }
    
    $finalContent = $headerBlock.TrimEnd() + "`n`n## 3. Raw Infrastructure Audit Violations`n*(The underlying data capturing the exact scale of the technical debt to be addressed across the project.)*`n" + ($newBody -join "`n")
    Set-Content -Path $file -Value $finalContent -Encoding UTF8
}
