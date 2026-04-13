# Game Asset Ingestion Model

## Purpose

This document defines the game asset ingestion layer for the LLM Workflow platform. It establishes how engine-specific and mixed game assets are inventoried, parsed, normalized, and governed as evidence.

## Scope

- Asset family taxonomy
- Provenance and license normalization
- Inventory vs descriptor parsing vs deep extraction boundaries
- Spritesheet and atlas parsing
- Marketplace asset handling (Epic, Fab, generic)
- RPG Maker and Unreal asset intake

---

## Asset Family Taxonomy

The platform classifies game assets into the following families:

| Family | Examples | Typical Formats |
|--------|----------|-----------------|
| `spritesheets` | Character animations, UI elements, effects | `.png` + `.json` sidecar |
| `tilemaps` | Level data, tile grids, collision layers | `.tmx`, `.json`, `.tsx` |
| `plugins` | Engine extensions, editor tools | `.js`, `.uplugin`, `.gd` |
| `rpgmaker` | Character sheets, faces, tilesets, audio, plugins | `.png`, `.ogg`, `.js` |
| `unreal` | Descriptors, modules, plugin references | `.uplugin`, `.uproject` |
| `epic` | Marketplace-bundled assets, Fab content | `.json` manifest, `.uasset` |
| `shared` | Cross-engine bundles, generic textures, audio | `.png`, `.wav`, `.mp3`, `.fbx` |

---

## Support Level Boundaries

The platform explicitly distinguishes three levels of support for every asset family. This prevents overclaim and ensures operators understand what is safe to rely on.

### 1. Inventory Support

**What it means**: The platform can detect, catalog, and classify the asset file in a project tree. File name, size, path, and family are recorded.

**What it does NOT mean**: The content is parsed, interpreted, or validated.

**Families with inventory support**:
- All families in the taxonomy above.
- Unreal binary assets (`.uasset`, `.umap`, `.ubulk`, `.uexp`) are inventory-only.
- Epic/Fab packaged bundles are inventory-only until provenance metadata is available.

### 2. Descriptor Parsing Support

**What it means**: The platform can parse human-readable metadata files that describe the asset or project structure. This includes JSON manifests, plugin descriptors, and project files.

**What it does NOT mean**: Binary or complex content formats are deeply interpreted.

**Families with descriptor parsing support**:
- `unreal`: `.uplugin`, `.uproject`
- `rpgmaker`: `Game.rmmzproject`, plugin headers
- `plugins`: RPG Maker plugin annotations, Unreal plugin descriptors
- `epic`: marketplace JSON manifests, bundle descriptors
- `spritesheets`: JSON atlas sidecars (Aseprite, TexturePacker)

### 3. Deep Extraction Support

**What it means**: The platform can parse and meaningfully extract internal structure from the asset format itself. This is the highest level of support and is only justified when safe parsing is available.

**What it does NOT mean**: All files in a family are deeply extracted. Many remain inventory-only or descriptor-only.

**Families with deep extraction support**:
- `spritesheets`: Aseprite JSON exports, generic frame-based JSON atlases
- `shared`: Simple metadata sidecars when schema is known
- `rpgmaker`: Plugin code and parameter extraction via `RPGMakerPluginParser`

**Explicitly NOT deep-extracted**:
- Unreal binary assets (`.uasset`, `.umap`, `.ubulk`, `.uexp`)
- Epic/Fab binary bundles
- Raw texture/image pixels (no image decoding pipeline)
- Audio waveforms (no audio content parsing)
- Tilemap binary formats without a safe sidecar parser

---

## Provenance Fields

Marketplace and vendor-derived assets carry provenance metadata that must be preserved for governance and review.

### Normalized Provenance Schema

```powershell
@{
    marketplace     = "epic"          # epic | fab | generic
    seller          = "Publisher Name"
    assetId         = "abc-123"
    assetName       = "Medieval Weapons Pack"
    url             = "https://..."
    purchaseDate    = "2026-01-15"
    entitlementType = "purchase"      # purchase | license | subscription | unknown
    sourceAuthority = 0.85
    raw             = @{ ... }
    normalizedAt    = "2026-04-13T10:00:00Z"
}
```

### Marketplace Detection

`MarketplaceProvenanceNormalizer.ps1` detects the source from:
- URL domain hints (`fab.com`, `unrealengine.com/marketplace`)
- Explicit `marketplace` field
- Known identifier fields (`fabId`, `catalogItemId`)

### Supported Marketplaces

| Marketplace | Key Hints | Source Authority |
|-------------|-----------|------------------|
| Epic Games Marketplace | `unrealengine.com/marketplace`, `catalogItemId` | 0.85 |
| Fab | `fab.com`, `fabId` | 0.85 |
| Generic | No strong hints | 0.60 |

---

## License Normalization

Asset licenses are normalized into five categories to simplify redistribution and review policy decisions.

### License Taxonomy

| Category | Description | Redistribution Default |
|----------|-------------|------------------------|
| `original` | Created in-house, self-authored | Allowed |
| `oss` | Open source license (MIT, Apache, GPL, etc.) | Allowed |
| `cc` | Creative Commons (CC0, CC-BY, etc.) | Allowed |
| `proprietary` | Commercial/purchased, all rights reserved | Denied |
| `restricted` | Non-commercial, educational, editorial, internal | Denied |

### License Normalization Schema

```powershell
@{
    category              = "proprietary"
    displayName           = "Commercial License"
    raw                   = "Commercial License"
    redistributionAllowed = $false
    requiresAttribution   = $true
    requiresReview        = $true
    normalizedAt          = "2026-04-13T10:00:00Z"
}
```

### Redistribution Safety

`Test-AssetLicenseRedistribution` enforces the following defaults:
- `original`, `oss`: allowed
- `cc`: allowed (with attribution flag set)
- `proprietary`, `restricted`: denied

Operators can override via explicit flags in the raw metadata (`redistributionAllowed`, `redistributable`, `canRedistribute`).

---

## Spritesheet and Atlas Ingestion

### Spritesheet Parser

`SpriteSheetParser.ps1` handles:
- Aseprite JSON export format
- Generic frame-based JSON spritesheets

### Output Fields

```powershell
@{
    assetType    = "spritesheet"
    sourcePath   = "..."
    baseImagePath = "..."
    format       = "aseprite-json"
    frameCount   = 12
    frames       = @(...)
    animations   = @(...)
    meta         = @{ ... }
}
```

### Atlas Parser

`AtlasMetadataParser.ps1` handles:
- TexturePacker JSON hash and array formats
- Generic atlas JSON with `frames` and `meta`

---

## Unreal and Epic Intake Boundaries

### Safe Metadata Layer (First Class)
- `.uplugin` — plugin descriptors
- `.uproject` — project descriptors

These are fully parsed, normalized, and promoted to evidence.

### Inventory-Only Layer
- `.uasset`, `.umap`, `.ubulk`, `.uexp`
- Epic/Fab binary bundles

These are cataloged by path, size, and provenance only. Deep extraction is explicitly out of scope pending further justification.

### Provenance Layer
- Marketplace JSON manifests
- Purchase/entitlement records
- License files bundled with the asset

These are parsed and normalized into the provenance and license schemas.

---

## Module Reference

| Module | Functions | Support Level |
|--------|-----------|---------------|
| `SpriteSheetParser.ps1` | `New-SpriteSheetParser`, `Read-SpriteSheetJson`, `Read-AsepriteJson`, `Export-SpriteSheetManifest` | Deep Extraction |
| `AtlasMetadataParser.ps1` | `New-AtlasMetadataParser`, `Read-AtlasJson`, `Get-AtlasFrames`, `Get-AtlasRegions` | Deep Extraction |
| `MarketplaceProvenanceNormalizer.ps1` | `New-MarketplaceProvenanceNormalizer`, `Normalize-MarketplaceProvenance`, `Get-MarketplaceSourceAuthority` | Descriptor Parsing |
| `AssetLicenseNormalizer.ps1` | `New-AssetLicenseNormalizer`, `Normalize-AssetLicense`, `Test-AssetLicenseRedistribution` | Descriptor Parsing |
| `RPGMakerAssetCatalogParser.ps1` | `Invoke-RPGMakerAssetCatalogParse`, `Get-RPGMakerAssetEntries`, `Test-RPGMakerAssetCatalog` | Inventory + Descriptor |
| `UnrealDescriptorParser.ps1` | `Invoke-UnrealDescriptorParse`, `Test-UnrealDescriptor` | Deep Extraction |

---

## Acceptance Criteria

- Every asset family maps to one or more support levels (inventory, descriptor, deep extraction).
- No binary engine asset is claimed as deeply extracted.
- Marketplace content preserves provenance, license, and engine family classification.
- License normalization prevents silent redistribution of restricted or proprietary assets.
- Spritesheet and atlas parsers produce normalized manifests for downstream evidence use.
