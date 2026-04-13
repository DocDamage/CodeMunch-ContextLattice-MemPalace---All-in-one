#requires -Version 5.1
<#
.SYNOPSIS
    Unreal Engine descriptor parser for the LLM Workflow Phase 4 Structured Extraction Pipeline.

.DESCRIPTION
    Parses Unreal Engine `.uplugin` and `.uproject` descriptor files and extracts
    normalized metadata for plugins, modules, project dependencies, platform targets,
    and compatibility hints.

.NOTES
    File Name      : UnrealDescriptorParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : Unreal Engine 4.x, Unreal Engine 5.x
#>

Set-StrictMode -Version Latest

function Invoke-UnrealDescriptorParse {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,

        [Parameter()]
        [ValidateSet('plugin', 'project', 'auto')]
        [string]$DescriptorType = 'auto'
    )

    process {
        $sourceFile = '<inline>'
        $rawContent = $Content

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "File not found: $Path"
            }

            $sourceFile = (Resolve-Path -LiteralPath $Path).Path
            $rawContent = Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8
        }

        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            throw 'Descriptor content is empty.'
        }

        $resolvedType = Resolve-UnrealDescriptorType -DescriptorType $DescriptorType -Path $sourceFile
        $descriptor = ConvertFrom-UnrealDescriptorJson -Content $rawContent
        $metadata = Get-UnrealDescriptorMetadata -Descriptor $descriptor -DescriptorType $resolvedType -SourceFile $sourceFile
        $modules = Get-UnrealDescriptorModules -Descriptor $descriptor
        $plugins = Get-UnrealDescriptorPlugins -Descriptor $descriptor
        $targets = Get-UnrealDescriptorTargetPlatforms -Descriptor $descriptor -DescriptorType $resolvedType
        $compatibility = Get-UnrealDescriptorCompatibility -Descriptor $descriptor -DescriptorType $resolvedType -Modules $modules -Plugins $plugins

        return [ordered]@{
            descriptorType = $resolvedType
            fileVersion = Get-UnrealDescriptorPropertyValue -Descriptor $descriptor -PropertyNames @('FileVersion', 'FileVersionUE', 'PluginFileVersion') -DefaultValue 0
            version = Get-UnrealDescriptorPropertyValue -Descriptor $descriptor -PropertyNames @('Version') -DefaultValue 0
            versionName = Get-UnrealDescriptorPropertyValue -Descriptor $descriptor -PropertyNames @('VersionName') -DefaultValue ''
            friendlyName = $metadata.friendlyName
            name = $metadata.name
            description = $metadata.description
            category = $metadata.category
            engineAssociation = $metadata.engineAssociation
            createdBy = $metadata.createdBy
            createdByUrl = $metadata.createdByUrl
            docsUrl = $metadata.docsUrl
            marketplaceUrl = $metadata.marketplaceUrl
            supportUrl = $metadata.supportUrl
            canContainContent = $metadata.canContainContent
            isBetaVersion = $metadata.isBetaVersion
            isExperimentalVersion = $metadata.isExperimentalVersion
            enabledByDefault = $metadata.enabledByDefault
            installed = $metadata.installed
            targetPlatforms = $targets
            modules = $modules
            plugins = $plugins
            sourceFile = $sourceFile
            parsedAt = [DateTime]::UtcNow.ToString('o')
            compatibility = $compatibility
        }
    }
}

function Get-UnrealDescriptorMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor,

        [Parameter(Mandatory = $true)]
        [ValidateSet('plugin', 'project')]
        [string]$DescriptorType,

        [Parameter()]
        [string]$SourceFile = ''
    )

    $fileNameStem = if ([string]::IsNullOrWhiteSpace($SourceFile) -or $SourceFile -eq '<inline>') {
        ''
    } else {
        [System.IO.Path]::GetFileNameWithoutExtension($SourceFile)
    }

    return [ordered]@{
        name = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('Name') -DefaultValue $fileNameStem
        friendlyName = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('FriendlyName') -DefaultValue $fileNameStem
        description = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('Description') -DefaultValue ''
        category = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('Category') -DefaultValue ''
        engineAssociation = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('EngineAssociation') -DefaultValue ''
        createdBy = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('CreatedBy') -DefaultValue ''
        createdByUrl = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('CreatedByURL', 'CreatedByUrl') -DefaultValue ''
        docsUrl = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('DocsURL', 'DocsUrl') -DefaultValue ''
        marketplaceUrl = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('MarketplaceURL', 'MarketplaceUrl') -DefaultValue ''
        supportUrl = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('SupportURL', 'SupportUrl') -DefaultValue ''
        canContainContent = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('CanContainContent') -DefaultValue $false)
        isBetaVersion = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('IsBetaVersion') -DefaultValue $false)
        isExperimentalVersion = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('IsExperimentalVersion') -DefaultValue $false)
        enabledByDefault = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('EnabledByDefault') -DefaultValue ($DescriptorType -eq 'project'))
        installed = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('Installed') -DefaultValue $false)
    }
}

function Get-UnrealDescriptorModules {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor
    )

    $modules = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('Modules') -DefaultValue @()
    $results = @()

    foreach ($module in @($modules)) {
        $results += [ordered]@{
            name = Get-UnrealDescriptorPropertyValue -Descriptor $module -PropertyNames @('Name') -DefaultValue ''
            type = Get-UnrealDescriptorPropertyValue -Descriptor $module -PropertyNames @('Type') -DefaultValue ''
            loadingPhase = Get-UnrealDescriptorPropertyValue -Descriptor $module -PropertyNames @('LoadingPhase') -DefaultValue ''
            platformAllowList = Get-UnrealDescriptorArrayValue -Descriptor $module -PropertyNames @('PlatformAllowList', 'WhitelistPlatforms')
            platformDenyList = Get-UnrealDescriptorArrayValue -Descriptor $module -PropertyNames @('PlatformDenyList', 'BlacklistPlatforms')
            targetAllowList = Get-UnrealDescriptorArrayValue -Descriptor $module -PropertyNames @('TargetAllowList', 'WhitelistTargets')
            targetDenyList = Get-UnrealDescriptorArrayValue -Descriptor $module -PropertyNames @('TargetDenyList', 'BlacklistTargets')
            additionalDependencies = Get-UnrealDescriptorArrayValue -Descriptor $module -PropertyNames @('AdditionalDependencies')
        }
    }

        return ,@($results)
}

function Get-UnrealDescriptorPlugins {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor
    )

    $plugins = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('Plugins') -DefaultValue @()
    $results = @()

    foreach ($plugin in @($plugins)) {
        $results += [ordered]@{
            name = Get-UnrealDescriptorPropertyValue -Descriptor $plugin -PropertyNames @('Name') -DefaultValue ''
            enabled = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $plugin -PropertyNames @('Enabled') -DefaultValue $false)
            optional = [bool](Get-UnrealDescriptorPropertyValue -Descriptor $plugin -PropertyNames @('Optional') -DefaultValue $false)
            description = Get-UnrealDescriptorPropertyValue -Descriptor $plugin -PropertyNames @('Description') -DefaultValue ''
            marketplaceUrl = Get-UnrealDescriptorPropertyValue -Descriptor $plugin -PropertyNames @('MarketplaceURL', 'MarketplaceUrl') -DefaultValue ''
            supportedTargetPlatforms = Get-UnrealDescriptorArrayValue -Descriptor $plugin -PropertyNames @('SupportedTargetPlatforms')
            platformAllowList = Get-UnrealDescriptorArrayValue -Descriptor $plugin -PropertyNames @('PlatformAllowList', 'WhitelistPlatforms')
            targetAllowList = Get-UnrealDescriptorArrayValue -Descriptor $plugin -PropertyNames @('TargetAllowList', 'WhitelistTargets')
        }
    }

    return ,@($results)
}

function Get-UnrealDescriptorTargetPlatforms {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor,

        [Parameter(Mandatory = $true)]
        [ValidateSet('plugin', 'project')]
        [string]$DescriptorType
    )

    $platforms = @()
    $platforms += Get-UnrealDescriptorArrayValue -Descriptor $Descriptor -PropertyNames @('SupportedTargetPlatforms')
    $platforms += Get-UnrealDescriptorArrayValue -Descriptor $Descriptor -PropertyNames @('TargetPlatforms')

    if ($DescriptorType -eq 'plugin') {
        $platforms += Get-UnrealDescriptorArrayValue -Descriptor $Descriptor -PropertyNames @('PlatformAllowList', 'WhitelistPlatforms')
    }

    return ,@($platforms | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
}

function Get-UnrealDescriptorCompatibility {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor,

        [Parameter(Mandatory = $true)]
        [ValidateSet('plugin', 'project')]
        [string]$DescriptorType,

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$Modules,

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$Plugins
    )

    $engineAssociation = [string](Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames @('EngineAssociation') -DefaultValue '')
    $hasEditorModule = @($Modules | Where-Object { $_.type -eq 'Editor' }).Count -gt 0
    $hasRuntimeModule = @($Modules | Where-Object { $_.type -eq 'Runtime' }).Count -gt 0

    return [ordered]@{
        descriptorType = $DescriptorType
        engineAssociation = $engineAssociation
        hasExplicitEngineAssociation = -not [string]::IsNullOrWhiteSpace($engineAssociation)
        moduleCount = @($Modules).Count
        pluginReferenceCount = @($Plugins).Count
        hasEditorModule = $hasEditorModule
        hasRuntimeModule = $hasRuntimeModule
        likelyEngineMajor = Get-UnrealLikelyEngineMajor -EngineAssociation $engineAssociation
    }
}

function Test-UnrealDescriptor {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,

        [Parameter()]
        [ValidateSet('plugin', 'project', 'auto')]
        [string]$DescriptorType = 'auto'
    )

    try {
        $null = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Invoke-UnrealDescriptorParse -Path $Path -DescriptorType $DescriptorType
        } else {
            Invoke-UnrealDescriptorParse -Content $Content -DescriptorType $DescriptorType
        }
        return $true
    }
    catch {
        return $false
    }
}

function ConvertFrom-UnrealDescriptorJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $normalized = $Content -replace '(?ms)/\*.*?\*/', ''
    $normalized = ($normalized -split "`r?`n" | ForEach-Object {
        $_ -replace '^\s*//.*$', ''
    }) -join "`n"
    $normalized = $normalized -replace ',\s*(\]|\})', '$1'

    try {
        return $normalized | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse Unreal descriptor JSON: $($_.Exception.Message)"
    }
}

function Resolve-UnrealDescriptorType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('plugin', 'project', 'auto')]
        [string]$DescriptorType,

        [Parameter()]
        [string]$Path = ''
    )

    if ($DescriptorType -ne 'auto') {
        return $DescriptorType
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.uplugin' { return 'plugin' }
        '.uproject' { return 'project' }
        default { return 'project' }
    }
}

function Get-UnrealDescriptorPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor,

        [Parameter(Mandatory = $true)]
        [string[]]$PropertyNames,

        [Parameter()]
        $DefaultValue = $null
    )

    foreach ($propertyName in $PropertyNames) {
        if ($Descriptor -is [System.Collections.IDictionary] -and $Descriptor.Contains($propertyName)) {
            return $Descriptor[$propertyName]
        }

        $property = $Descriptor.PSObject.Properties[$propertyName]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    return $DefaultValue
}

function Get-UnrealDescriptorArrayValue {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        $Descriptor,

        [Parameter(Mandatory = $true)]
        [string[]]$PropertyNames
    )

    $value = Get-UnrealDescriptorPropertyValue -Descriptor $Descriptor -PropertyNames $PropertyNames -DefaultValue @()
    if ($null -eq $value) {
        return @()
    }

    return ,@($value)
}

function Get-UnrealLikelyEngineMajor {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$EngineAssociation
    )

    if ([string]::IsNullOrWhiteSpace($EngineAssociation)) {
        return 'Unknown'
    }

    if ($EngineAssociation -match '^5') { return '5.x' }
    if ($EngineAssociation -match '^4') { return '4.x' }
    return 'Unknown'
}

Export-ModuleMember -Function @(
    'Invoke-UnrealDescriptorParse',
    'Get-UnrealDescriptorMetadata',
    'Get-UnrealDescriptorModules',
    'Get-UnrealDescriptorPlugins',
    'Get-UnrealDescriptorTargetPlatforms',
    'Get-UnrealDescriptorCompatibility',
    'Test-UnrealDescriptor'
)
