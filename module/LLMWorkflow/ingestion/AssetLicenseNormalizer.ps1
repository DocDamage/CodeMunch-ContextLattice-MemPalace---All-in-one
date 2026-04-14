#requires -Version 5.1
<#
.SYNOPSIS
    Normalizes asset license metadata for game asset ingestion.

.DESCRIPTION
    Converts diverse license inputs into a normalized taxonomy:
    original, oss, cc, proprietary, restricted.

    Also provides redistribution safety checks based on the normalized
    license category and any additional flags.

.PARAMETER LicenseInput
    Raw license string or hashtable.

.PARAMETER LicenseCategory
    Explicit license category override.

.OUTPUTS
    System.Collections.Hashtable. Normalized license record.

.NOTES
    File Name      : AssetLicenseNormalizer.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'AssetLicenseNormalizer'

$script:LicenseCategoryMap = [ordered]@{
    'original' = @('original', 'self', 'own', 'author')
    'oss' = @('oss', 'opensource', 'open source', 'mit', 'apache', 'apache-2.0', 'apache 2.0', 'bsd', 'gpl', 'lgpl', 'mozilla', 'mpl')
    'cc' = @('cc', 'creative commons', 'cc0', 'cc-by', 'cc-by-sa', 'cc-by-nc', 'cc-by-nd', 'cc-by-nc-sa', 'cc-by-nc-nd')
    'proprietary' = @('proprietary', 'commercial', 'paid', 'purchased', 'marketplace')
    'restricted' = @('restricted', 'editorial', 'nc', 'non-commercial', 'noncommercial', 'personal', 'edu', 'educational', 'confidential', 'internal')
}

<#
.SYNOPSIS
    Creates a new asset license normalizer configuration.

.OUTPUTS
    System.Collections.Hashtable. Normalizer configuration object.
#>
function New-AssetLicenseNormalizer {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return [ordered]@{
        normalizerName = 'AssetLicenseNormalizer'
        normalizerVersion = $script:ModuleVersion
        supportedCategories = @('original', 'oss', 'cc', 'proprietary', 'restricted')
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Normalizes a license input into the standard schema.

.DESCRIPTION
    Maps raw license strings or objects into a normalized license record
    with category, display name, redistribution flags, and review requirements.

.PARAMETER LicenseInput
    Raw license string or hashtable.

.PARAMETER LicenseCategory
    Optional explicit category override.

.OUTPUTS
    System.Collections.Hashtable. Normalized license record.
#>
function Normalize-AssetLicense {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$LicenseInput,

        [Parameter()]
        [ValidateSet('original', 'oss', 'cc', 'proprietary', 'restricted')]
        [string]$LicenseCategory = ''
    )

    $rawString = ''
    $rawObj = @{}

    if ($LicenseInput -is [string]) {
        $rawString = $LicenseInput
    }
    elseif ($LicenseInput -is [hashtable] -or $LicenseInput -is [pscustomobject]) {
        $ht = @{}
        if ($LicenseInput -is [pscustomobject]) {
            $LicenseInput | Get-Member -MemberType NoteProperty | ForEach-Object {
                $ht[$_.Name] = $LicenseInput.$($_.Name)
            }
        }
        else {
            $ht = $LicenseInput
        }
        $rawObj = $ht
        if ($ht.Contains('license')) { $rawString = [string]$ht.license }
        elseif ($ht.Contains('name')) { $rawString = [string]$ht.name }
        elseif ($ht.Contains('type')) { $rawString = [string]$ht.type }
    }

    $detectedCategory = if ([string]::IsNullOrWhiteSpace($LicenseCategory)) {
        Resolve-LicenseCategory -LicenseString $rawString
    } else {
        $LicenseCategory
    }

    $displayName = if ($rawObj.Contains('displayName')) { $rawObj.displayName } elseif (-not [string]::IsNullOrWhiteSpace($rawString)) { $rawString } else { $detectedCategory }
    $requiresAttribution = $detectedCategory -in @('cc', 'oss', 'proprietary')
    $requiresReview = $detectedCategory -in @('restricted', 'proprietary')
    $redistributionAllowed = Test-AssetLicenseRedistribution -NormalizedCategory $detectedCategory -RawObject $rawObj

    return [ordered]@{
        category = $detectedCategory
        displayName = $displayName
        raw = $rawString
        rawObject = $rawObj
        redistributionAllowed = $redistributionAllowed
        requiresAttribution = $requiresAttribution
        requiresReview = $requiresReview
        normalizedAt = [DateTime]::UtcNow.ToString('o')
        normalizerVersion = $script:ModuleVersion
    }
}

<#
.SYNOPSIS
    Tests whether redistribution is allowed for a normalized license.

.DESCRIPTION
    Checks the normalized license category and any explicit flags in
    the raw metadata to determine if redistribution is permitted.

.PARAMETER NormalizedCategory
    Normalized license category.

.PARAMETER RawObject
    Optional raw license metadata for additional flag checks.

.OUTPUTS
    System.Boolean. $true if redistribution appears allowed.
#>
function Test-AssetLicenseRedistribution {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('original', 'oss', 'cc', 'proprietary', 'restricted')]
        [string]$NormalizedCategory,

        [Parameter()]
        [hashtable]$RawObject = @{}
    )

    # Explicit override in raw object
    if ($RawObject.Contains('redistributionAllowed')) {
        return [bool]$RawObject.redistributionAllowed
    }
    if ($RawObject.Contains('redistributable')) {
        return [bool]$RawObject.redistributable
    }
    if ($RawObject.Contains('canRedistribute')) {
        return [bool]$RawObject.canRedistribute
    }

    switch ($NormalizedCategory) {
        'original' { return $true }
        'oss' { return $true }
        'cc' {
            # Most CC licenses allow redistribution with conditions; CC0 freely
            # We default to true but flag for review on NC or ND variants
            return $true
        }
        'proprietary' { return $false }
        'restricted' { return $false }
        default { return $false }
    }
}

# Private helper: resolve license category from string
function Resolve-LicenseCategory {
    param(
        [string]$LicenseString
    )

    if ([string]::IsNullOrWhiteSpace($LicenseString)) {
        return 'restricted'
    }

    $normalized = $LicenseString.ToLower().Trim()

    foreach ($category in $script:LicenseCategoryMap.Keys) {
        foreach ($alias in $script:LicenseCategoryMap[$category]) {
            if ($normalized -eq $alias) {
                return $category
            }
        }
    }

    # Fallback heuristics for clear cases before broad matching
    if ($normalized -match 'non-commercial|non commercial|personal use only|editorial use|internal use|confidential') {
        return 'restricted'
    }
    if ($normalized -match '(^|[^\w-])proprietary($|[^\w-])|all rights reserved|\(c\)|(^|[^\w-])copyright($|[^\w-])') {
        return 'proprietary'
    }
    if ($normalized -match '(^|[^\w-])mit($|[^\w-])|apache|bsd|gpl|mozilla|open source') {
        return 'oss'
    }
    if ($normalized -match 'cc0|creative commons|cc-by|cc by') {
        return 'cc'
    }

    foreach ($category in $script:LicenseCategoryMap.Keys) {
        foreach ($alias in $script:LicenseCategoryMap[$category]) {
            $pattern = '(^|[^\w-])' + [regex]::Escape($alias) + '($|[^\w-])'
            if ($normalized -match $pattern) {
                return $category
            }
        }
    }

    return 'restricted'
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-AssetLicenseNormalizer',
        'Normalize-AssetLicense',
        'Test-AssetLicenseRedistribution'
    )
}

}

