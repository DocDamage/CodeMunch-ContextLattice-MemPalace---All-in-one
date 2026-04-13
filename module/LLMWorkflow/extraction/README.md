# LLM Workflow Extraction Module (Phase 4)

## RPGMakerPluginParser.ps1

PowerShell module for parsing RPG Maker MZ/MV plugin headers to extract structured metadata.

### Functions

| Function | Description |
|----------|-------------|
| `ConvertFrom-RPGMakerPlugin` | Main parser for .js plugin files |
| `Get-PluginMetadata` | Extracts plugin header info (@plugindesc, @author, @version, @target) |
| `Get-PluginParameters` | Extracts @param definitions with types, defaults, and constraints |
| `Get-PluginCommands` | Extracts @command definitions with arguments |
| `Get-PluginDependencies` | Extracts dependency info (@reqPlugin, @reqVersion, etc.) |
| `New-PluginManifest` | Creates normalized manifest object from parsed components |
| `Test-RPGMakerPlugin` | Validates if a file is an RPG Maker plugin |
| `Export-RPGMakerPluginManifest` | Exports manifest to JSON file |

### Usage

```powershell
# Import the module
Import-Module ./module/LLMWorkflow/extraction/RPGMakerPluginParser.ps1

# Parse a plugin file
$manifest = ConvertFrom-RPGMakerPlugin -Path "MyPlugin.js"

# Access extracted data
$manifest.pluginName
$manifest.parameters
$manifest.commands
$manifest.dependencies

# Export to JSON
ConvertFrom-RPGMakerPlugin -Path "MyPlugin.js" -AsJson | Set-Content "manifest.json"

# Validate a plugin file
if (Test-RPGMakerPlugin -Path "Unknown.js") {
    # Process valid plugin
}
```

### Output Schema

```powershell
@{
    fileType = "rmmz_plugin"
    pluginName = "PluginName"
    description = "Plugin description"
    author = "Author Name"
    version = "1.0.0"
    targetEngine = "MZ"  # or "MV"
    parameters = @(...)
    commands = @(...)
    dependencies = @(...)
}
```

### Supported Annotations

- `@plugindesc` - Plugin name/description
- `@author` - Plugin author
- `@version` - Plugin version
- `@target` - Target engine (MZ/MV)
- `@help` - Help text
- `@param` - Parameter definition
- `@text` - Display name for params/commands
- `@desc` / `@description` - Description text
- `@type` - Data type (string, number, boolean, select, etc.)
- `@default` - Default value
- `@min` / `@max` - Numeric constraints
- `@command` - Plugin command definition
- `@arg` - Command argument
- `@reqPlugin` - Required plugin dependency
- `@reqVersion` - Required plugin version
- `@reqMV` / `@reqMZ` - Engine version requirements

### Phase 4 Status

This module is part of the Phase 4 Structured Extraction Pipeline for the LLM Workflow platform.

## UnrealDescriptorParser.ps1

PowerShell module for parsing Unreal Engine `.uplugin` and `.uproject` descriptor files.

### Functions

| Function | Description |
|----------|-------------|
| `Invoke-UnrealDescriptorParse` | Main parser for Unreal descriptor files |
| `Get-UnrealDescriptorMetadata` | Extracts descriptor metadata and authoring fields |
| `Get-UnrealDescriptorModules` | Extracts Unreal module declarations |
| `Get-UnrealDescriptorPlugins` | Extracts plugin reference declarations |
| `Get-UnrealDescriptorTargetPlatforms` | Extracts supported and targeted platforms |
| `Get-UnrealDescriptorCompatibility` | Summarizes engine and module compatibility hints |
| `Test-UnrealDescriptor` | Validates whether a descriptor can be parsed |

### Output Schema

```powershell
@{
    descriptorType = "plugin"  # or "project"
    fileVersion = 3
    friendlyName = "Example Plugin"
    engineAssociation = "5.4"
    modules = @(...)
    plugins = @(...)
    targetPlatforms = @(...)
    compatibility = @{ likelyEngineMajor = "5.x" }
}
```

## RPGMakerAssetCatalogParser.ps1

PowerShell module for cataloging RPG Maker MV/MZ project asset directories into normalized asset families.

### Functions

| Function | Description |
|----------|-------------|
| `Invoke-RPGMakerAssetCatalogParse` | Main parser for RPG Maker project asset trees |
| `Get-RPGMakerAssetEntries` | Enumerates normalized entries for a single asset family |
| `Test-RPGMakerAssetCatalog` | Validates whether a directory looks like an RPG Maker project |
| `Export-RPGMakerAssetCatalog` | Exports the normalized catalog to JSON |

### Output Schema

```powershell
@{
    engineFamily = "rpgmaker"
    detectedVariant = "MZ"  # or "MV"
    assetFamilies = @{
        characters = @{ entries = @(...) }
        faces = @{ entries = @(...) }
        tilesets = @{ entries = @(...) }
        bgm = @{ entries = @(...) }
        plugins = @{ entries = @(...) }
    }
    statistics = @{
        totalAssets = 42
        pluginCount = 8
        parsedPluginCount = 6
    }
}
```
