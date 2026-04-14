#requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for Document Ingestion pipeline components.

.DESCRIPTION
    Covers DocumentNormalizer, DocumentEvidenceClassifier, and
    adapter mock behavior for DoclingAdapter and TikaAdapter.
#>

BeforeAll {
    $IngestionPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'module') 'LLMWorkflow') 'ingestion'

    @(
        'DocumentNormalizer.ps1',
        'DocumentEvidenceClassifier.ps1',
        'DoclingAdapter.ps1',
        'TikaAdapter.ps1'
    ) | ForEach-Object {
        $path = Join-Path $IngestionPath $_
        if (Test-Path $path) {
            . $path
        }
    }
}

Describe "DocumentNormalizer" {
    Context "New-DocumentNormalizer" {
        It "Returns default configuration" {
            $norm = New-DocumentNormalizer
            $norm.normalizerName | Should -Be 'DocumentNormalizer'
            $norm.preferredChunkSize | Should -Be 2000
            $norm.chunkOverlap | Should -Be 200
        }
    }

    Context "Normalize-DocumentOutput" {
        It "Normalizes a simple extraction result" {
            $raw = [ordered]@{
                success = $true
                sourcePath = 'C:\docs\test.pdf'
                format = 'pdf'
                text = "Page one.`n`nPage two."
                pages = @(
                    @{ pageNumber = 1; text = "Page one." },
                    @{ pageNumber = 2; text = "Page two." }
                )
                confidence = 0.90
                errors = @()
                warnings = @()
                extractedAt = '2026-04-13T10:00:00Z'
            }

            $result = Normalize-DocumentOutput -ExtractionResult $raw -EngineName 'docling'
            $result.sourcePath | Should -Be 'C:\docs\test.pdf'
            $result.format | Should -Be 'pdf'
            $result.engine | Should -Be 'docling'
            $result.success | Should -Be $true
            $result.pages | Should -HaveCount 2
            $result.chunks.Count | Should -BeGreaterThan 0
        }

        It "Creates a single page when pages array is missing but text exists" {
            $raw = [ordered]@{
                success = $true
                sourcePath = 'C:\docs\test.docx'
                format = 'docx'
                text = "Only text."
                confidence = 0.85
                errors = @()
                warnings = @()
                extractedAt = '2026-04-13T10:00:00Z'
            }

            $result = Normalize-DocumentOutput -ExtractionResult $raw -EngineName 'tika'
            $result.pages | Should -HaveCount 1
            $result.pages[0].pageNumber | Should -Be 1
            $result.pages[0].text | Should -Be 'Only text.'
        }
    }

    Context "Split-DocumentByPage" {
        It "Splits long text into multiple chunks" {
            $text = "Paragraph one." * 200
            $chunks = Split-DocumentByPage -PageText $text -PageNumber 1 -Normalizer (New-DocumentNormalizer -PreferredChunkSize 500 -ChunkOverlap 50)
            $chunks.Count | Should -BeGreaterThan 1
            $chunks[0].pageNumber | Should -Be 1
            $chunks[0].chunkId | Should -Be 'p1-c1'
        }

        It "Returns empty array for empty text" {
            $chunks = Split-DocumentByPage -PageText '' -PageNumber 1
            $chunks | Should -HaveCount 0
        }
    }

    Context "Merge-DocumentChunks" {
        It "Merges chunks back into text" {
            $chunks = @(
                @{ chunkId = 'p1-c1'; pageNumber = 1; text = 'Hello' },
                @{ chunkId = 'p1-c2'; pageNumber = 1; text = 'World' }
            )
            $merged = Merge-DocumentChunks -Chunks $chunks
            $merged | Should -Match 'Hello'
            $merged | Should -Match 'World'
        }

        It "Inserts page breaks when requested" {
            $chunks = @(
                @{ chunkId = 'p1-c1'; pageNumber = 1; text = 'Page 1' },
                @{ chunkId = 'p2-c1'; pageNumber = 2; text = 'Page 2' }
            )
            $merged = Merge-DocumentChunks -Chunks $chunks -IncludePageBreaks
            $merged | Should -Match "`f"
        }
    }
}

Describe "DocumentEvidenceClassifier" {
    Context "New-DocumentEvidenceClassifier" {
        It "Returns default classifier configuration" {
            $cl = New-DocumentEvidenceClassifier
            $cl.classifierName | Should -Be 'DocumentEvidenceClassifier'
            $cl.minimumQualityThreshold | Should -Be 0.60
            $cl.ocrWeight | Should -Be 0.40
            $cl.structuralWeight | Should -Be 0.35
            $cl.authorityWeight | Should -Be 0.25
        }
    }

    Context "Get-DocumentEvidenceScore" {
        It "Scores a high-quality document highly" {
            $doc = [ordered]@{
                success = $true
                sourcePath = 'C:\docs\test.pdf'
                format = 'pdf'
                engine = 'docling'
                confidence = 0.95
                pages = @(
                    @{ pageNumber = 1; text = ('A' * 1500) + "`n# Heading`n- Item 1`n- Item 2" },
                    @{ pageNumber = 2; text = ('B' * 1500) }
                )
                chunks = @(
                    @{ chunkId = 'p1-c1'; pageNumber = 1; text = ('A' * 1500) },
                    @{ chunkId = 'p1-c2'; pageNumber = 1; text = "# Heading`n- Item 1`n- Item 2" },
                    @{ chunkId = 'p2-c1'; pageNumber = 2; text = ('B' * 1500) }
                )
            }

            $score = Get-DocumentEvidenceScore -NormalizedDocument $doc
            $score.passed | Should -Be $true
            $score.overallScore | Should -BeGreaterThan 0.60
            $score.scores.sourceAuthority | Should -BeGreaterThan 0.90
        }

        It "Fails a document with extraction failure" {
            $doc = [ordered]@{
                success = $false
                sourcePath = 'C:\docs\bad.pdf'
                format = 'pdf'
                engine = 'docling'
                confidence = 0.0
                pages = @()
                chunks = @()
                errors = @('Docling failed')
            }

            $score = Get-DocumentEvidenceScore -NormalizedDocument $doc
            $score.passed | Should -Be $false
            $score.issues | Should -Not -BeNullOrEmpty
        }

        It "Flags low-ocr-yield for mostly empty pages" {
            $doc = [ordered]@{
                success = $true
                sourcePath = 'C:\docs\scan.pdf'
                format = 'pdf'
                engine = 'tika'
                confidence = 0.75
                pages = @(
                    @{ pageNumber = 1; text = 'A' },
                    @{ pageNumber = 2; text = 'B' },
                    @{ pageNumber = 3; text = 'C' }
                )
                chunks = @()
            }

            $score = Get-DocumentEvidenceScore -NormalizedDocument $doc
            $issue = $score.issues | Where-Object { $_.type -eq 'low-ocr-yield' }
            $issue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Test-DocumentEvidenceQuality" {
        It "Returns true for passing documents" {
            $doc = [ordered]@{
                success = $true
                format = 'pdf'
                engine = 'docling'
                confidence = 0.95
                pages = @( @{ pageNumber = 1; text = ('X' * 2000) } )
                chunks = @( @{ chunkId = 'p1-c1'; pageNumber = 1; text = ('X' * 2000) } )
            }

            Test-DocumentEvidenceQuality -NormalizedDocument $doc | Should -Be $true
        }

        It "Returns false for failing documents" {
            $doc = [ordered]@{
                success = $false
                format = 'pdf'
                engine = 'docling'
                confidence = 0.0
                pages = @()
                chunks = @()
                errors = @('Fail')
            }

            Test-DocumentEvidenceQuality -NormalizedDocument $doc | Should -Be $false
        }
    }
}

Describe "DoclingAdapter (Mocked / Availability)" {
    Context "New-DoclingAdapter" {
        It "Creates an adapter with defaults" {
            $adapter = New-DoclingAdapter
            $adapter.adapterName | Should -Be 'DoclingAdapter'
            $adapter.timeoutSeconds | Should -Be 300
            $adapter.supportedFormats | Should -Contain '.pdf'
        }

        It "Falls back to literal 'python' when candidate resolution fails unexpectedly" {
            Mock Get-Command {
                throw [System.InvalidOperationException]::new('unexpected command resolution failure')
            }

            $adapter = New-DoclingAdapter
            $adapter.pythonPath | Should -Be 'python'
        }
    }

    Context "Test-DoclingAvailable" {
        It "Returns false when Python path is invalid" {
            $adapter = New-DoclingAdapter -PythonPath 'C:\NonExistent\python.exe'
            Test-DoclingAvailable -Adapter $adapter | Should -Be $false
        }
    }

    Context "Invoke-DoclingExtraction" {
        It "Returns failure for missing file" {
            $result = Invoke-DoclingExtraction -FilePath 'C:\NoSuchFile.pdf'
            $result.success | Should -Be $false
            $result.errors | Should -Contain "File not found: C:\NoSuchFile.pdf"
        }

        It "Returns missing-file failure when path resolution throws unexpectedly" {
            Mock Resolve-Path {
                throw [System.IO.IOException]::new('filesystem probe failed')
            }

            $result = Invoke-DoclingExtraction -FilePath 'C:\NoSuchFile.pdf'
            $result.success | Should -Be $false
            $result.errors | Should -Contain "File not found: C:\NoSuchFile.pdf"
        }

        It "Returns failure for unsupported format" {
            $tmp = Join-Path $TestDrive 'test.xyz'
            'data' | Set-Content -LiteralPath $tmp
            $result = Invoke-DoclingExtraction -FilePath $tmp
            $result.success | Should -Be $false
            $result.errors | Should -Contain "Unsupported format: .xyz"
        }
    }
}

Describe "TikaAdapter (Mocked / Availability)" {
    Context "New-TikaAdapter" {
        It "Creates an adapter with defaults" {
            $adapter = New-TikaAdapter
            $adapter.adapterName | Should -Be 'TikaAdapter'
            $adapter.tikaUrl | Should -Be 'http://localhost:9998'
            $adapter.timeoutSeconds | Should -Be 120
        }
    }

    Context "Test-TikaAvailable" {
        It "Returns false when Tika server is unreachable" {
            $adapter = New-TikaAdapter -TikaUrl 'http://localhost:59999'
            Test-TikaAvailable -Adapter $adapter | Should -Be $false
        }
    }

    Context "Invoke-TikaExtraction" {
        It "Returns failure for missing file" {
            $result = Invoke-TikaExtraction -FilePath 'C:\NoSuchFile.pdf'
            $result.success | Should -Be $false
            $result.errors | Should -Contain "File not found: C:\NoSuchFile.pdf"
        }

        It "Returns tika-unavailable when server is down" {
            $tmp = Join-Path $TestDrive 'test.docx'
            'data' | Set-Content -LiteralPath $tmp
            $adapter = New-TikaAdapter -TikaUrl 'http://localhost:59999'
            $result = Invoke-TikaExtraction -FilePath $tmp -Adapter $adapter
            $result.success | Should -Be $false
            $result.engine | Should -Be 'tika-unavailable'
        }
    }
}
