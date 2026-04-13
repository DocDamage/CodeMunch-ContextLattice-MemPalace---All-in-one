#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Generates SBOMs for release artifacts in the LLM Workflow platform.
.DESCRIPTION
    Uses syft-like logic to scan the project directory, identify key artifacts
    (PowerShell modules, JSON configs, Docker images), and generate a
    CycloneDX-compatible JSON SBOM. Safe to run without Syft installed.
.NOTES
    File: Invoke-SBOMBuild.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

#region Private Helpers

function New-SBOMComponent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter()]
        [string]$Version = "",

        [Parameter()]
        [string]$FilePath = "",

        [Parameter()]
        [string]$Purl = "",

        [Parameter()]
        [hashtable]$Properties = @{}
    )

    $bomRef = "urn:llmworkflow:component:$Type`:$Name`:$([Guid]::NewGuid().ToString('N'))"

    $component = [ordered]@{
        type = $Type
        name = $Name
        'bom-ref' = $bomRef
    }

    if (-not [string]::IsNullOrEmpty($Version)) {
        $component['version'] = $Version
    }

    if (-not [string]::IsNullOrEmpty($Purl)) {
        $component['purl'] = $Purl
    }

    if ($Properties.Count -gt 0) {
        $component['properties'] = @()
        foreach ($key in $Properties.Keys) {
            $component['properties'] += [ordered]@{
                name = $key
                value = $Properties[$key]
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($FilePath)) {
        if (-not $component.Contains('properties')) {
            $component['properties'] = @()
        }
        $component['properties'] += [ordered]@{
            name = 'discoveredPath'
            value = $FilePath
        }
    }

    return [pscustomobject]$component
}

function Get-ModuleVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleManifestPath
    )

    try {
        $content = Get-Content -LiteralPath $ModuleManifestPath -Raw -ErrorAction SilentlyContinue
        $regex = [regex]'ModuleVersion\s*=\s*[''"]([^''"]+)[''"]'
        $match = $regex.Match($content)
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }
    catch {
        Write-Verbose "[Invoke-SBOMBuild] Could not read manifest: $ModuleManifestPath"
    }

    return "0.0.0"
}

function Get-JsonConfigMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $props = @{}
    try {
        $json = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($json.version) {
            $props['configVersion'] = $json.version
        }
        if ($json.schemaVersion) {
            $props['schemaVersion'] = $json.schemaVersion
        }
        if ($json.name) {
            $props['configName'] = $json.name
        }
    }
    catch {
        Write-Verbose "[Invoke-SBOMBuild] Could not parse JSON config: $ConfigPath"
    }

    return $props
}

function Get-DockerImageReference {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DockerfilePath
    )

    try {
        $lines = Get-Content -LiteralPath $DockerfilePath -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^\s*FROM\s+(.+)$') {
                $image = $Matches[1].Trim()
                return $image
            }
        }
    }
    catch {
        Write-Verbose "[Invoke-SBOMBuild] Could not read Dockerfile: $DockerfilePath"
    }

    return ""
}

#endregion

#region Public Functions

function Get-SBOMComponents {
    <#
    .SYNOPSIS
        Discovers SBOM components from the project directory.
    .DESCRIPTION
        Scans the project for PowerShell modules, JSON configs, Dockerfiles,
        and other artifacts, returning an array of CycloneDX-style component
        objects.
    .PARAMETER ProjectRoot
        The root directory to scan. Defaults to the current working directory.
    .EXAMPLE
        $components = Get-SBOMComponents -ProjectRoot .
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Get-Location).Path
    )

    $components = @()

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot"
    }

    # Scan PowerShell modules
    $moduleFiles = Get-ChildItem -Path $ProjectRoot -File -Recurse -Include '*.psd1' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\node_modules\*' -and $_.FullName -notlike '*\.git\*' }

    foreach ($file in $moduleFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $version = Get-ModuleVersion -ModuleManifestPath $file.FullName
        $relativePath = $file.FullName.Substring((Resolve-Path -LiteralPath $ProjectRoot).Path.Length + 1)

        $components += New-SBOMComponent `
            -Name $name `
            -Type 'library' `
            -Version $version `
            -FilePath $relativePath `
            -Purl "pkg:powershell/$name@$version" `
            -Properties @{ language = 'PowerShell'; manifestType = 'PowerShellDataFile' }
    }

    # Scan JSON configs
    $configFiles = Get-ChildItem -Path $ProjectRoot -File -Recurse -Include '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\node_modules\*' -and $_.FullName -notlike '*\.git\*' }

    foreach ($file in $configFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $relativePath = $file.FullName.Substring((Resolve-Path -LiteralPath $ProjectRoot).Path.Length + 1)
        $metadata = Get-JsonConfigMetadata -ConfigPath $file.FullName

        $components += New-SBOMComponent `
            -Name $name `
            -Type 'configuration' `
            -FilePath $relativePath `
            -Purl "pkg:json/$name" `
            -Properties $metadata
    }

    # Scan Dockerfiles
    $dockerFiles = Get-ChildItem -Path $ProjectRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Dockerfile*' -and $_.FullName -notlike '*\node_modules\*' -and $_.FullName -notlike '*\.git\*' }

    foreach ($file in $dockerFiles) {
        $name = $file.Name
        $relativePath = $file.FullName.Substring((Resolve-Path -LiteralPath $ProjectRoot).Path.Length + 1)
        $imageRef = Get-DockerImageReference -DockerfilePath $file.FullName

        $props = @{ containerType = 'Dockerfile' }
        if ($imageRef) {
            $props['baseImage'] = $imageRef
        }

        $components += New-SBOMComponent `
            -Name $name `
            -Type 'container' `
            -FilePath $relativePath `
            -Purl "pkg:docker/$name" `
            -Properties $props
    }

    # Scan docker-compose files
    $composeFiles = Get-ChildItem -Path $ProjectRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -like 'docker-compose*.yml' -or $_.Name -like 'docker-compose*.yaml') -and $_.FullName -notlike '*\node_modules\*' -and $_.FullName -notlike '*\.git\*' }

    foreach ($file in $composeFiles) {
        $name = $file.Name
        $relativePath = $file.FullName.Substring((Resolve-Path -LiteralPath $ProjectRoot).Path.Length + 1)

        $components += New-SBOMComponent `
            -Name $name `
            -Type 'container' `
            -FilePath $relativePath `
            -Purl "pkg:docker-compose/$name" `
            -Properties @{ containerType = 'DockerCompose' }
    }

    # Scan PowerShell scripts that are not modules
    $scriptFiles = Get-ChildItem -Path $ProjectRoot -File -Recurse -Include '*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\node_modules\*' -and $_.FullName -notlike '*\.git\*' }

    foreach ($file in $scriptFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $relativePath = $file.FullName.Substring((Resolve-Path -LiteralPath $ProjectRoot).Path.Length + 1)

        # Skip if already accounted for as a module manifest
        $manifestPath = Join-Path $file.DirectoryName "$name.psd1"
        if (Test-Path -LiteralPath $manifestPath) {
            continue
        }

        $components += New-SBOMComponent `
            -Name $name `
            -Type 'file' `
            -FilePath $relativePath `
            -Purl "pkg:powershell/$name" `
            -Properties @{ language = 'PowerShell'; artifactType = 'script' }
    }

    return $components
}

function Invoke-SBOMBuild {
    <#
    .SYNOPSIS
        Generates a CycloneDX-compatible JSON SBOM for the project.
    .DESCRIPTION
        Discovers components via Get-SBOMComponents and assembles a
        CycloneDX 1.5-compatible SBOM document. Writes the SBOM to the
        specified output path.
    .PARAMETER ProjectRoot
        The root directory to scan. Defaults to the current working directory.
    .PARAMETER OutputPath
        The path to write the SBOM JSON file. Defaults to sbom.json.
    .PARAMETER ToolName
        Optional tool name to record in the SBOM metadata.
    .EXAMPLE
        Invoke-SBOMBuild -ProjectRoot . -OutputPath ./sbom.json
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Get-Location).Path,

        [Parameter()]
        [string]$OutputPath = "sbom.json",

        [Parameter()]
        [string]$ToolName = 'Invoke-SBOMBuild (Syft-compatible)'
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot"
    }

    $components = Get-SBOMComponents -ProjectRoot $ProjectRoot

    $sbom = [ordered]@{
        'bomFormat' = 'CycloneDX'
        'specVersion' = '1.5'
        'serialNumber' = "urn:uuid:$([Guid]::NewGuid().ToString())"
        'version' = 1
        'metadata' = [ordered]@{
            'timestamp' = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            'tools' = @(
                [ordered]@{
                    'vendor' = 'LLMWorkflow'
                    'name' = $ToolName
                    'version' = '1.0.0'
                }
            )
            'component' = [ordered]@{
                'type' = 'application'
                'name' = [System.IO.Path]::GetFileName((Resolve-Path -LiteralPath $ProjectRoot).Path)
                'version' = '1.0.0'
                'bom-ref' = 'urn:llmworkflow:application:root'
            }
        }
        'components' = @($components | ForEach-Object {
            $ordered = [ordered]@{}
            foreach ($prop in $_.PSObject.Properties.Name) {
                $ordered[$prop] = $_.$prop
            }
            $ordered
        })
    }

    if (@($components).Count -gt 0) {
        $sbom['dependencies'] = @(
            [ordered]@{
                'ref' = $sbom.metadata.component.'bom-ref'
                'dependsOn' = @($components | ForEach-Object { $_.'bom-ref' })
            }
        )
    }

    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $sbom | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8

    return [pscustomobject]@{
        success = $true
        outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
        componentCount = @($components).Count
        tool = $ToolName
        timestamp = $sbom.metadata.timestamp
    }
}

#endregion
