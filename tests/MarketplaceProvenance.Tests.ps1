#requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for MarketplaceProvenanceNormalizer and AssetLicenseNormalizer.

.DESCRIPTION
    Validates marketplace provenance detection, normalization,
    license categorization, and redistribution safety checks.
#>

BeforeAll {
    $IngestionPath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'module') 'LLMWorkflow') 'ingestion'

    @(
        'MarketplaceProvenanceNormalizer.ps1',
        'AssetLicenseNormalizer.ps1'
    ) | ForEach-Object {
        $path = Join-Path $IngestionPath $_
        if (Test-Path $path) {
            . $path
        }
    }
}

Describe "MarketplaceProvenanceNormalizer" {
    Context "New-MarketplaceProvenanceNormalizer" {
        It "Returns normalizer configuration" {
            $norm = New-MarketplaceProvenanceNormalizer
            $norm.normalizerName | Should -Be 'MarketplaceProvenanceNormalizer'
            $norm.supportedMarketplaces | Should -Contain 'epic'
            $norm.supportedMarketplaces | Should -Contain 'fab'
            $norm.supportedMarketplaces | Should -Contain 'generic'
        }
    }

    Context "Get-MarketplaceSourceAuthority" {
        It "Detects Fab from URL" {
            $input = @{ url = 'https://www.fab.com/listings/my-asset' }
            Get-MarketplaceSourceAuthority -ProvenanceInput $input | Should -Be 'fab'
        }

        It "Detects Epic from URL" {
            $input = @{ url = 'https://www.unrealengine.com/marketplace/en-US/product/my-asset' }
            Get-MarketplaceSourceAuthority -ProvenanceInput $input | Should -Be 'epic'
        }

        It "Detects Fab from fabId" {
            $input = @{ fabId = 'fab-123' }
            Get-MarketplaceSourceAuthority -ProvenanceInput $input | Should -Be 'fab'
        }

        It "Detects Epic from catalogItemId" {
            $input = @{ catalogItemId = 'epic-456' }
            Get-MarketplaceSourceAuthority -ProvenanceInput $input | Should -Be 'epic'
        }

        It "Falls back to generic when no hints present" {
            $input = @{ seller = 'Unknown' }
            Get-MarketplaceSourceAuthority -ProvenanceInput $input | Should -Be 'generic'
        }
    }

    Context "Normalize-MarketplaceProvenance" {
        It "Normalizes Epic provenance" {
            $input = @{
                seller = 'Epic Publisher'
                catalogItemId = 'abc-123'
                title = 'Epic Asset'
                productSlug = 'epic-asset'
                purchaseDate = '2026-01-01'
                entitlementType = 'purchase'
            }
            $result = Normalize-MarketplaceProvenance -ProvenanceInput $input
            $result.marketplace | Should -Be 'epic'
            $result.seller | Should -Be 'Epic Publisher'
            $result.assetId | Should -Be 'abc-123'
            $result.assetName | Should -Be 'Epic Asset'
            $result.url | Should -Match 'unrealengine.com'
            $result.entitlementType | Should -Be 'purchase'
            $result.sourceAuthority | Should -Be 0.85
        }

        It "Normalizes Fab provenance" {
            $input = @{
                creator = 'Fab Creator'
                fabId = 'fab-789'
                title = 'Fab Asset'
                slug = 'fab-asset'
                purchaseDate = '2026-02-01'
                entitlementType = 'license'
            }
            $result = Normalize-MarketplaceProvenance -ProvenanceInput $input
            $result.marketplace | Should -Be 'fab'
            $result.seller | Should -Be 'Fab Creator'
            $result.assetId | Should -Be 'fab-789'
            $result.assetName | Should -Be 'Fab Asset'
            $result.url | Should -Match 'fab.com'
            $result.entitlementType | Should -Be 'license'
            $result.sourceAuthority | Should -Be 0.85
        }

        It "Normalizes generic provenance" {
            $input = @{
                vendor = 'Some Vendor'
                id = 'gen-001'
                name = 'Generic Asset'
                link = 'https://example.com/asset'
                acquiredDate = '2026-03-01'
                licenseType = 'commercial'
            }
            $result = Normalize-MarketplaceProvenance -ProvenanceInput $input
            $result.marketplace | Should -Be 'generic'
            $result.seller | Should -Be 'Some Vendor'
            $result.assetId | Should -Be 'gen-001'
            $result.assetName | Should -Be 'Generic Asset'
            $result.sourceAuthority | Should -Be 0.60
        }

        It "Respects explicit marketplace override" {
            $input = @{ seller = 'S'; id = '1'; url = 'https://example.com' }
            $result = Normalize-MarketplaceProvenance -ProvenanceInput $input -MarketplaceName 'epic'
            $result.marketplace | Should -Be 'epic'
            $result.sourceAuthority | Should -Be 0.85
        }
    }
}

Describe "AssetLicenseNormalizer" {
    Context "New-AssetLicenseNormalizer" {
        It "Returns normalizer configuration" {
            $norm = New-AssetLicenseNormalizer
            $norm.normalizerName | Should -Be 'AssetLicenseNormalizer'
            $norm.supportedCategories | Should -Contain 'original'
            $norm.supportedCategories | Should -Contain 'restricted'
        }
    }

    Context "Normalize-AssetLicense" {
        It "Normalizes MIT as oss" {
            $result = Normalize-AssetLicense -LicenseInput 'MIT License'
            $result.category | Should -Be 'oss'
            $result.redistributionAllowed | Should -Be $true
            $result.requiresAttribution | Should -Be $true
        }

        It "Normalizes CC0 as cc" {
            $result = Normalize-AssetLicense -LicenseInput 'CC0'
            $result.category | Should -Be 'cc'
            $result.redistributionAllowed | Should -Be $true
        }

        It "Normalizes proprietary string" {
            $result = Normalize-AssetLicense -LicenseInput 'All Rights Reserved'
            $result.category | Should -Be 'proprietary'
            $result.redistributionAllowed | Should -Be $false
            $result.requiresReview | Should -Be $true
        }

        It "Normalizes restricted string" {
            $result = Normalize-AssetLicense -LicenseInput 'Non-Commercial Use Only'
            $result.category | Should -Be 'restricted'
            $result.redistributionAllowed | Should -Be $false
            $result.requiresReview | Should -Be $true
        }

        It "Normalizes original string" {
            $result = Normalize-AssetLicense -LicenseInput 'Original Work'
            $result.category | Should -Be 'original'
            $result.redistributionAllowed | Should -Be $true
            $result.requiresAttribution | Should -Be $false
        }

        It "Uses explicit category override" {
            $result = Normalize-AssetLicense -LicenseInput 'Some random text' -LicenseCategory 'oss'
            $result.category | Should -Be 'oss'
        }

        It "Handles hashtable input with license key" {
            $input = @{ license = 'Apache-2.0'; displayName = 'Apache 2.0' }
            $result = Normalize-AssetLicense -LicenseInput $input
            $result.category | Should -Be 'oss'
            $result.displayName | Should -Be 'Apache 2.0'
        }

        It "Defaults empty input to restricted" {
            $result = Normalize-AssetLicense -LicenseInput ''
            $result.category | Should -Be 'restricted'
            $result.redistributionAllowed | Should -Be $false
        }
    }

    Context "Test-AssetLicenseRedistribution" {
        It "Returns true for original" {
            Test-AssetLicenseRedistribution -NormalizedCategory 'original' | Should -Be $true
        }

        It "Returns true for oss" {
            Test-AssetLicenseRedistribution -NormalizedCategory 'oss' | Should -Be $true
        }

        It "Returns true for cc" {
            Test-AssetLicenseRedistribution -NormalizedCategory 'cc' | Should -Be $true
        }

        It "Returns false for proprietary" {
            Test-AssetLicenseRedistribution -NormalizedCategory 'proprietary' | Should -Be $false
        }

        It "Returns false for restricted" {
            Test-AssetLicenseRedistribution -NormalizedCategory 'restricted' | Should -Be $false
        }

        It "Respects explicit override in raw object" {
            $raw = @{ redistributionAllowed = $true }
            Test-AssetLicenseRedistribution -NormalizedCategory 'proprietary' -RawObject $raw | Should -Be $true
        }
    }
}
