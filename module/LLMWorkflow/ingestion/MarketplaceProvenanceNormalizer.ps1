#requires -Version 5.1
<#
.SYNOPSIS
    Normalizes marketplace asset provenance metadata.

.DESCRIPTION
    Converts marketplace-specific asset provenance information into a
    consistent schema. Supports Epic Games Store, Fab, and generic
    marketplace sources.

    Normalized fields include: marketplace, seller, assetId, url,
    purchaseDate, entitlementType, and sourceAuthority.

.PARAMETER ProvenanceInput
    Raw provenance hashtable from a marketplace source.

.PARAMETER MarketplaceName
    Name of the marketplace (epic, fab, generic).

.OUTPUTS
    System.Collections.Hashtable. Normalized provenance record.

.NOTES
    File Name      : MarketplaceProvenanceNormalizer.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'MarketplaceProvenanceNormalizer'

<#
.SYNOPSIS
    Creates a new marketplace provenance normalizer configuration.

.OUTPUTS
    System.Collections.Hashtable. Normalizer configuration object.
#>
function New-MarketplaceProvenanceNormalizer {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return [ordered]@{
        normalizerName = 'MarketplaceProvenanceNormalizer'
        normalizerVersion = $script:ModuleVersion
        supportedMarketplaces = @('epic', 'fab', 'generic')
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Normalizes a marketplace provenance input into the standard schema.

.DESCRIPTION
    Maps raw marketplace fields to the normalized provenance schema.
    Detects marketplace type from input hints if not explicitly specified.

.PARAMETER ProvenanceInput
    Raw provenance hashtable.

.PARAMETER MarketplaceName
    Explicit marketplace name. If omitted, attempts auto-detection.

.OUTPUTS
    System.Collections.Hashtable. Normalized provenance record.
#>
function Normalize-MarketplaceProvenance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$ProvenanceInput,

        [Parameter()]
        [ValidateSet('epic', 'fab', 'generic')]
        [string]$MarketplaceName = ''
    )

    $detected = if ([string]::IsNullOrWhiteSpace($MarketplaceName)) {
        Get-MarketplaceSourceAuthority -ProvenanceInput $ProvenanceInput
    } else {
        $MarketplaceName.ToLower()
    }

    $normalized = [ordered]@{
        marketplace = $detected
        seller = ''
        assetId = ''
        assetName = ''
        url = ''
        purchaseDate = ''
        entitlementType = 'unknown'
        sourceAuthority = 0.5
        raw = $ProvenanceInput
        normalizedAt = [DateTime]::UtcNow.ToString('o')
        normalizerVersion = $script:ModuleVersion
    }

    switch ($detected) {
        'epic' {
            $normalized.seller = if ($ProvenanceInput.Contains('seller')) { $ProvenanceInput.seller } elseif ($ProvenanceInput.Contains('publisher')) { $ProvenanceInput.publisher } else { '' }
            $normalized.assetId = if ($ProvenanceInput.Contains('assetId')) { $ProvenanceInput.assetId } elseif ($ProvenanceInput.Contains('catalogItemId')) { $ProvenanceInput.catalogItemId } elseif ($ProvenanceInput.Contains('id')) { $ProvenanceInput.id } else { '' }
            $normalized.assetName = if ($ProvenanceInput.Contains('assetName')) { $ProvenanceInput.assetName } elseif ($ProvenanceInput.Contains('title')) { $ProvenanceInput.title } else { '' }
            $normalized.url = if ($ProvenanceInput.Contains('url')) { $ProvenanceInput.url } elseif ($ProvenanceInput.Contains('productSlug')) { "https://www.unrealengine.com/marketplace/en-US/product/$($ProvenanceInput.productSlug)" } else { '' }
            $normalized.purchaseDate = if ($ProvenanceInput.Contains('purchaseDate')) { $ProvenanceInput.purchaseDate } else { '' }
            $normalized.entitlementType = if ($ProvenanceInput.Contains('entitlementType')) { $ProvenanceInput.entitlementType } else { 'purchase' }
            $normalized.sourceAuthority = 0.85
        }
        'fab' {
            $normalized.seller = if ($ProvenanceInput.Contains('seller')) { $ProvenanceInput.seller } elseif ($ProvenanceInput.Contains('creator')) { $ProvenanceInput.creator } else { '' }
            $normalized.assetId = if ($ProvenanceInput.Contains('assetId')) { $ProvenanceInput.assetId } elseif ($ProvenanceInput.Contains('fabId')) { $ProvenanceInput.fabId } elseif ($ProvenanceInput.Contains('id')) { $ProvenanceInput.id } else { '' }
            $normalized.assetName = if ($ProvenanceInput.Contains('assetName')) { $ProvenanceInput.assetName } elseif ($ProvenanceInput.Contains('title')) { $ProvenanceInput.title } else { '' }
            $normalized.url = if ($ProvenanceInput.Contains('url')) { $ProvenanceInput.url } elseif ($ProvenanceInput.Contains('slug')) { "https://www.fab.com/listings/$($ProvenanceInput.slug)" } else { '' }
            $normalized.purchaseDate = if ($ProvenanceInput.Contains('purchaseDate')) { $ProvenanceInput.purchaseDate } else { '' }
            $normalized.entitlementType = if ($ProvenanceInput.Contains('entitlementType')) { $ProvenanceInput.entitlementType } else { 'license' }
            $normalized.sourceAuthority = 0.85
        }
        'generic' {
            $normalized.seller = if ($ProvenanceInput.Contains('seller')) { $ProvenanceInput.seller } elseif ($ProvenanceInput.Contains('vendor')) { $ProvenanceInput.vendor } elseif ($ProvenanceInput.Contains('creator')) { $ProvenanceInput.creator } else { '' }
            $normalized.assetId = if ($ProvenanceInput.Contains('assetId')) { $ProvenanceInput.assetId } elseif ($ProvenanceInput.Contains('id')) { $ProvenanceInput.id } else { '' }
            $normalized.assetName = if ($ProvenanceInput.Contains('assetName')) { $ProvenanceInput.assetName } elseif ($ProvenanceInput.Contains('title')) { $ProvenanceInput.title } elseif ($ProvenanceInput.Contains('name')) { $ProvenanceInput.name } else { '' }
            $normalized.url = if ($ProvenanceInput.Contains('url')) { $ProvenanceInput.url } elseif ($ProvenanceInput.Contains('link')) { $ProvenanceInput.link } else { '' }
            $normalized.purchaseDate = if ($ProvenanceInput.Contains('purchaseDate')) { $ProvenanceInput.purchaseDate } elseif ($ProvenanceInput.Contains('acquiredDate')) { $ProvenanceInput.acquiredDate } else { '' }
            $normalized.entitlementType = if ($ProvenanceInput.Contains('entitlementType')) { $ProvenanceInput.entitlementType } elseif ($ProvenanceInput.Contains('licenseType')) { $ProvenanceInput.licenseType } else { 'unknown' }
            $normalized.sourceAuthority = 0.60
        }
    }

    return $normalized
}

<#
.SYNOPSIS
    Detects the marketplace source and returns its authority level.

.DESCRIPTION
    Analyzes provenance input for marketplace hints such as domain names,
    specific fields, or known identifiers. Returns the marketplace name.

.PARAMETER ProvenanceInput
    Raw provenance hashtable.

.OUTPUTS
    System.String. Detected marketplace name.
#>
function Get-MarketplaceSourceAuthority {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$ProvenanceInput
    )

    $url = ''
    if ($ProvenanceInput.Contains('url')) { $url = [string]$ProvenanceInput.url }
    elseif ($ProvenanceInput.Contains('link')) { $url = [string]$ProvenanceInput.link }
    elseif ($ProvenanceInput.Contains('productSlug')) { $url = [string]$ProvenanceInput.productSlug }
    elseif ($ProvenanceInput.Contains('slug')) { $url = [string]$ProvenanceInput.slug }

    $lowerUrl = $url.ToLower()

    if ($lowerUrl -match 'fab\.com' -or $ProvenanceInput.Contains('fabId')) {
        return 'fab'
    }
    if ($lowerUrl -match 'unrealengine\.com/marketplace' -or $lowerUrl -match 'epicgames\.com' -or $ProvenanceInput.Contains('catalogItemId')) {
        return 'epic'
    }

    if ($ProvenanceInput.Contains('marketplace')) {
        $mp = [string]$ProvenanceInput.marketplace
        if ($mp -in @('epic', 'fab', 'generic')) { return $mp }
        if ($mp -match 'epic') { return 'epic' }
        if ($mp -match 'fab') { return 'fab' }
    }

    return 'generic'
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-MarketplaceProvenanceNormalizer',
        'Normalize-MarketplaceProvenance',
        'Get-MarketplaceSourceAuthority'
    )
}

}

