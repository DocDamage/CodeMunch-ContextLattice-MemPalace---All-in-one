#requires -Version 5.1

Set-StrictMode -Version Latest

Describe "Compatibility curated-plugin fixtures" {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
        $script:CompatibilityModulePath = Join-Path $script:RepoRoot "module\LLMWorkflow\workflow\Compatibility.ps1"
        $script:FixtureRoot = Join-Path $PSScriptRoot "fixtures\compat\curated-plugin"

        . $script:CompatibilityModulePath

        function New-CuratedPluginHarness {
            param(
                [Parameter(Mandatory = $true)]
                [string]$FixtureName
            )

            $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
            $packsRoot = Join-Path $root "packs"
            $manifestRoot = Join-Path $packsRoot "manifests"
            $registryRoot = Join-Path $packsRoot "registries"

            New-Item -ItemType Directory -Path $manifestRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $registryRoot -Force | Out-Null

            $packId = "curated-plugin-pack"
            $manifest = @{
                packId = $packId
                domain = "game-dev"
                version = "1.0.0"
                status = "promoted"
                channel = "stable"
                toolkitConstraint = ">=0.4.0"
            }
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $manifestRoot "$packId.json") -Encoding UTF8

            $fixturePath = Join-Path $script:FixtureRoot "$FixtureName.sources.json"
            Copy-Item -LiteralPath $fixturePath -Destination (Join-Path $registryRoot "$packId.sources.json") -Force

            return $root
        }
    }

    It "treats active curated-plugin fixtures as compatible" {
        $root = New-CuratedPluginHarness -FixtureName "active"

        Push-Location $root
        try {
            $result = Test-CompatibilityMatrix -PackId "curated-plugin-pack"

            $result.overallStatus | Should -Be "compatible"
            $result.sources.Count | Should -Be 1
            $result.sources[0].sourceId | Should -Be "curated-plugin-stable"
            $result.sources[0].status | Should -Be "compatible"
        }
        finally {
            Pop-Location
        }
    }

    It "surfaces deprecated curated-plugin fixtures as warning" {
        $root = New-CuratedPluginHarness -FixtureName "deprecated"

        Push-Location $root
        try {
            $result = Test-CompatibilityMatrix -PackId "curated-plugin-pack"

            $result.overallStatus | Should -Be "warning"
            $result.sources.Count | Should -Be 1
            $result.sources[0].sourceId | Should -Be "curated-plugin-deprecated"
            $result.sources[0].status | Should -Be "warning"
            $result.sources[0].statusReason | Should -Match "deprecated"
        }
        finally {
            Pop-Location
        }
    }

    It "blocks quarantined curated-plugin fixtures as incompatible" {
        $root = New-CuratedPluginHarness -FixtureName "quarantined"

        Push-Location $root
        try {
            $result = Test-CompatibilityMatrix -PackId "curated-plugin-pack"

            $result.overallStatus | Should -Be "incompatible"
            $result.conflicts.Count | Should -Be 1
            $result.conflicts[0].type | Should -Be "source"
            $result.conflicts[0].sourceId | Should -Be "curated-plugin-quarantined"
            $result.sources[0].status | Should -Be "incompatible"
            $result.sources[0].statusReason | Should -Match "quarantined"
        }
        finally {
            Pop-Location
        }
    }

    It "blocks retired curated-plugin fixtures as incompatible" {
        $root = New-CuratedPluginHarness -FixtureName "retired"

        Push-Location $root
        try {
            $result = Test-CompatibilityMatrix -PackId "curated-plugin-pack"

            $result.overallStatus | Should -Be "incompatible"
            $result.conflicts.Count | Should -Be 1
            $result.conflicts[0].sourceId | Should -Be "curated-plugin-retired"
            $result.sources[0].status | Should -Be "incompatible"
            $result.sources[0].statusReason | Should -Match "retired"
        }
        finally {
            Pop-Location
        }
    }

    It "handles mixed curated-plugin fixture suites with both warning and incompatible signals" {
        $root = New-CuratedPluginHarness -FixtureName "mixed"

        Push-Location $root
        try {
            $result = Test-CompatibilityMatrix -PackId "curated-plugin-pack"

            $result.overallStatus | Should -Be "incompatible"
            $result.sources.Count | Should -Be 3
            ($result.sources | Where-Object { $_.status -eq "compatible" }).Count | Should -Be 1
            ($result.sources | Where-Object { $_.status -eq "warning" }).Count | Should -Be 1
            ($result.sources | Where-Object { $_.status -eq "incompatible" }).Count | Should -Be 1
            ($result.conflicts | Where-Object { $_.sourceId -eq "curated-plugin-behavior-override" }).Count | Should -Be 1
        }
        finally {
            Pop-Location
        }
    }

    It "pins curated-plugin refs into compatibility lock exports" {
        $root = New-CuratedPluginHarness -FixtureName "mixed"

        Push-Location $root
        try {
            $lockPath = Join-Path $root "compatibility.lock.json"
            $exportedPath = Export-CompatibilityLock -PackId "curated-plugin-pack" -Path $lockPath -PinSources
            $lock = Get-Content -LiteralPath $exportedPath -Raw | ConvertFrom-JsonToHashtable

            $lock.packId | Should -Be "curated-plugin-pack"
            $lock.sources.ContainsKey("curated-plugin-stable") | Should -Be $true
            $lock.sources.ContainsKey("curated-plugin-compat-shim") | Should -Be $true
            $lock.sources.ContainsKey("curated-plugin-behavior-override") | Should -Be $true
            $lock.sources["curated-plugin-stable"].pinnedRef | Should -Be "v2.4.1"
            $lock.sources["curated-plugin-compat-shim"].pinnedRef | Should -Be "v1.8.5"
            $lock.sources["curated-plugin-behavior-override"].pinnedRef | Should -Be "v2.0.0-beta.3"
        }
        finally {
            Pop-Location
        }
    }
}
