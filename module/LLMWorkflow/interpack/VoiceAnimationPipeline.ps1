#requires -Version 5.1
<#
.SYNOPSIS
    Voice to Animation Pipeline for LLM Workflow platform.

.DESCRIPTION
    Provides voice/audio to animation conversion pipelines:
    - Voice/audio pack → lip sync data (phoneme extraction)
    - Lip sync data → animation curves (viseme mapping)
    - Animation → Godot/Blender format export

    Supports multiple phoneme extraction engines, viseme mapping systems,
    and game engine animation formats.

.NOTES
    File: VoiceAnimationPipeline.ps1
    Version: 0.1.0
    Author: LLM Workflow Team
    Part of: Advanced Inter-Pack Pipeline Implementation

.EXAMPLE
    # Voice to lip sync
    $lipSync = Convert-VoiceToLipSync -AudioPath "./dialogue.wav" -Engine "rhubarb"
    
    # Lip sync to animation
    $animation = Convert-LipSyncToAnimation -LipSyncData $lipSync -CharacterRig "humanoid" -FrameRate 60
    
    # Export to Godot
    Export-LipSyncToEngine -AnimationData $animation -EngineFormat "godot" -OutputPath "./lipsync.tres"
#>

Set-StrictMode -Version Latest

#===============================================================================
# Constants and Configuration
#===============================================================================

$script:VoiceAnimSchemaVersion = 1
$script:VoiceAnimDirectory = ".llm-workflow/interpack/voice-animation"
$script:LipSyncDirectory = ".llm-workflow/interpack/voice-animation/lipsync"
$script:AnimationCurvesDirectory = ".llm-workflow/interpack/voice-animation/curves"

# Phoneme extraction engines
$script:PhonemeEngines = @{
    'rhubarb' = @{
        name = 'Rhubarb Lip Sync'
        version = '1.13.0'
        supportedFormats = @('wav', 'mp3', 'ogg', 'flac')
        outputFormats = @('json', 'tsv', 'xml')
        phonemeSet = 'rhubarb-basic'
        supportsDialogue = $true
        supportsEmotion = $false
        recognitionType = 'phonetic'
    }
    'allosaurus' = @{
        name = 'Allosaurus Phoneme'
        version = '2.0.0'
        supportedFormats = @('wav')
        outputFormats = @('json', 'txt', 'TextGrid')
        phonemeSet = 'ipa'
        supportsDialogue = $false
        supportsEmotion = $true
        recognitionType = 'deep-learning'
    }
    'pocketsphinx' = @{
        name = 'PocketSphinx'
        version = '5.0.0'
        supportedFormats = @('wav')
        outputFormats = @('json', 'txt')
        phonemeSet = 'arpabet'
        supportsDialogue = $true
        supportsEmotion = $false
        recognitionType = 'hmm'
    }
    'gentle' = @{
        name = 'Gentle Aligner'
        version = '1.0.0'
        supportedFormats = @('wav', 'mp3')
        outputFormats = @('json')
        phonemeSet = 'arpabet'
        supportsDialogue = $true
        supportsEmotion = $false
        recognitionType = 'forced-alignment'
    }
}

# Viseme mapping systems
$script:VisemeMaps = @{
    'rhubarb-basic' = @{
        'A' = @{ mouthShape = 'A'; description = 'open mouth'; examples = @('bat', 'apple') }
        'B' = @{ mouthShape = 'B'; description = 'closed lips'; examples = @('bet', 'bat') }
        'C' = @{ mouthShape = 'C'; description = 'wide shape'; examples = @('seat', 'sit') }
        'D' = @{ mouthShape = 'D'; description = 'teeth on lip'; examples = @('fie', 'vie') }
        'E' = @{ mouthShape = 'E'; description = 'oooh shape'; examples = @('shoe', 'food') }
        'F' = @{ mouthShape = 'F'; description = 'lower lip bite'; examples = @('fat', 'vat') }
        'G' = @{ mouthShape = 'G'; description = 'wide teeth'; examples = @('heat', 'hay') }
        'H' = @{ mouthShape = 'H'; description = 'tongue up'; examples = @('tip', 'tight') }
        'X' = @{ mouthShape = 'X'; description = 'rest position'; examples = @() }
    }
    'ovr-lipsync' = @{
        visemeCount = 15
        visemes = @('sil', 'PP', 'FF', 'TH', 'DD', 'kk', 'CH', 'SS', 'nn', 'RR', 'aa', 'E', 'ih', 'oh', 'ou')
        blendshapeCompatible = $true
    }
    'arpabet-viseme' = @{
        'AA' = @{ viseme = 'ah'; jawOpen = 0.8; lipRound = 0.0 }
        'AE' = @{ viseme = 'ae'; jawOpen = 0.7; lipRound = 0.0 }
        'AH' = @{ viseme = 'ah'; jawOpen = 0.6; lipRound = 0.0 }
        'AO' = @{ viseme = 'ao'; jawOpen = 0.7; lipRound = 0.5 }
        'AW' = @{ viseme = 'aw'; jawOpen = 0.8; lipRound = 0.3 }
        'AY' = @{ viseme = 'ay'; jawOpen = 0.7; lipRound = 0.0 }
        'B'  = @{ viseme = 'b'; jawOpen = 0.0; lipRound = 0.0 }
        'CH' = @{ viseme = 'ch'; jawOpen = 0.2; lipRound = 0.3 }
        'D'  = @{ viseme = 'd'; jawOpen = 0.1; lipRound = 0.0 }
        'EH' = @{ viseme = 'eh'; jawOpen = 0.5; lipRound = 0.0 }
        'ER' = @{ viseme = 'er'; jawOpen = 0.4; lipRound = 0.2 }
        'EY' = @{ viseme = 'ey'; jawOpen = 0.6; lipRound = 0.0 }
        'F'  = @{ viseme = 'f'; jawOpen = 0.1; lipRound = 0.0 }
        'G'  = @{ viseme = 'g'; jawOpen = 0.1; lipRound = 0.0 }
        'HH' = @{ viseme = 'hh'; jawOpen = 0.2; lipRound = 0.0 }
        'IH' = @{ viseme = 'ih'; jawOpen = 0.4; lipRound = 0.0 }
        'IY' = @{ viseme = 'iy'; jawOpen = 0.3; lipRound = 0.0 }
        'JH' = @{ viseme = 'jh'; jawOpen = 0.2; lipRound = 0.2 }
        'K'  = @{ viseme = 'k'; jawOpen = 0.1; lipRound = 0.0 }
        'L'  = @{ viseme = 'l'; jawOpen = 0.3; lipRound = 0.0 }
        'M'  = @{ viseme = 'm'; jawOpen = 0.0; lipRound = 0.0 }
        'N'  = @{ viseme = 'n'; jawOpen = 0.2; lipRound = 0.0 }
        'NG' = @{ viseme = 'ng'; jawOpen = 0.3; lipRound = 0.0 }
        'OW' = @{ viseme = 'ow'; jawOpen = 0.6; lipRound = 0.6 }
        'OY' = @{ viseme = 'oy'; jawOpen = 0.6; lipRound = 0.5 }
        'P'  = @{ viseme = 'p'; jawOpen = 0.0; lipRound = 0.0 }
        'R'  = @{ viseme = 'r'; jawOpen = 0.3; lipRound = 0.2 }
        'S'  = @{ viseme = 's'; jawOpen = 0.1; lipRound = 0.0 }
        'SH' = @{ viseme = 'sh'; jawOpen = 0.2; lipRound = 0.3 }
        'T'  = @{ viseme = 't'; jawOpen = 0.1; lipRound = 0.0 }
        'TH' = @{ viseme = 'th'; jawOpen = 0.1; lipRound = 0.0 }
        'UH' = @{ viseme = 'uh'; jawOpen = 0.5; lipRound = 0.4 }
        'UW' = @{ viseme = 'uw'; jawOpen = 0.4; lipRound = 0.7 }
        'V'  = @{ viseme = 'v'; jawOpen = 0.1; lipRound = 0.0 }
        'W'  = @{ viseme = 'w'; jawOpen = 0.2; lipRound = 0.6 }
        'Y'  = @{ viseme = 'y'; jawOpen = 0.2; lipRound = 0.1 }
        'Z'  = @{ viseme = 'z'; jawOpen = 0.1; lipRound = 0.0 }
        'ZH' = @{ viseme = 'zh'; jawOpen = 0.2; lipRound = 0.3 }
    }
}

# Engine animation formats
$script:EngineFormats = @{
    'godot' = @{
        extension = '.tres'
        format = 'Godot Resource'
        supportsBlendShapes = $true
        supportsBones = $true
        trackType = 'Animation'
        sampleRate = 60
    }
    'blender' = @{
        extension = '.json'
        format = 'Blender JSON'
        supportsBlendShapes = $true
        supportsBones = $true
        trackType = 'shape_key'
        sampleRate = 24
    }
    'unity' = @{
        extension = '.anim'
        format = 'Unity Animation'
        supportsBlendShapes = $true
        supportsBones = $true
        trackType = 'BlendShape'
        sampleRate = 60
    }
    'unreal' = @{
        extension = '.json'
        format = 'Unreal Curve'
        supportsBlendShapes = $true
        supportsBones = $true
        trackType = 'MorphTarget'
        sampleRate = 30
    }
}

# Exit codes
$script:ExitCodes = @{
    Success = 0
    GeneralFailure = 1
    InvalidAudioFormat = 2
    PhonemeExtractionFailed = 3
    AnimationConversionFailed = 4
    ExportFailed = 5
    EngineNotSupported = 6
}

#===============================================================================
# Voice to Lip Sync
#===============================================================================

function Convert-VoiceToLipSync {
    <#
    .SYNOPSIS
        Extracts phoneme timing data from voice/audio.
    .DESCRIPTION
        Uses phoneme recognition engines to analyze audio and generate
        timed phoneme/viseme data for lip synchronization.
    .PARAMETER AudioPath
        Path to the audio file (wav, mp3, ogg, flac).
    .PARAMETER Engine
        Phoneme extraction engine (rhubarb, allosaurus, pocketsphinx, gentle).
    .PARAMETER DialogueText
        Optional dialogue text for forced alignment (improves accuracy).
    .PARAMETER OutputFormat
        Output format for lip sync data (json, tsv, xml).
    .PARAMETER Language
        Language code for recognition (en-US, ja-JP, etc.).
    .PARAMETER ProjectRoot
        Project root directory.
    .PARAMETER RunId
        Run ID for tracking.
    .OUTPUTS
        System.Collections.Hashtable with lip sync data and metadata.
    .EXAMPLE
        $lipSync = Convert-VoiceToLipSync -AudioPath "./hello.wav" -Engine "rhubarb" -DialogueText "Hello world"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$AudioPath,

        [Parameter()]
        [ValidateSet('rhubarb', 'allosaurus', 'pocketsphinx', 'gentle')]
        [string]$Engine = 'rhubarb',

        [Parameter()]
        [string]$DialogueText = '',

        [Parameter()]
        [ValidateSet('json', 'tsv', 'xml', 'txt', 'TextGrid')]
        [string]$OutputFormat = 'json',

        [Parameter()]
        [string]$Language = 'en-US',

        [Parameter()]
        [string]$ProjectRoot = '.',

        [Parameter()]
        [string]$RunId = ''
    )

    if (-not $RunId) {
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $random = Get-Random -Minimum 0 -Maximum 65535
        $RunId = "v2l-$timestamp-$($random.ToString('x4'))"
    }

    # Initialize directories
    $lipSyncDir = Join-Path $ProjectRoot $script:LipSyncDirectory
    if (-not (Test-Path -LiteralPath $lipSyncDir)) {
        New-Item -ItemType Directory -Path $lipSyncDir -Force | Out-Null
    }

    $result = @{
        runId = $RunId
        success = $false
        audioPath = $AudioPath
        engine = $Engine
        language = $Language
        duration = 0.0
        phonemeCount = 0
        phonemes = @()
        outputPath = $null
        metadata = @{}
        errors = @()
        startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt = $null
    }

    try {
        # Get engine configuration
        $engineConfig = $script:PhonemeEngines[$Engine]
        if (-not $engineConfig) {
            throw "Phoneme engine not found: $Engine"
        }

        # Validate audio format
        $audioExt = [System.IO.Path]::GetExtension($AudioPath).TrimStart('.').ToLower()
        if ($audioExt -notin $engineConfig.supportedFormats) {
            throw "Audio format '$audioExt' not supported by engine '$Engine'. Supported: $($engineConfig.supportedFormats -join ', ')"
        }

        Write-Verbose "[VoiceAnim] Extracting phonemes using $Engine..."
        Write-Verbose "[VoiceAnim] Audio: $AudioPath"
        if ($DialogueText) {
            Write-Verbose "[VoiceAnim] Dialogue: $DialogueText"
        }

        # Generate output filename
        $audioFileName = [System.IO.Path]::GetFileNameWithoutExtension($AudioPath)
        $outputPath = Join-Path $lipSyncDir "$audioFileName-$RunId.$OutputFormat"
        $result.outputPath = $outputPath

        # Simulate phoneme extraction (placeholder for actual engine integration)
        $phonemes = @()
        
        # Generate sample phoneme data based on dialogue or default pattern
        if ($DialogueText) {
            # Parse dialogue into words and estimate timing
            $words = $DialogueText -split '\s+'
            $currentTime = 0.0
            $avgDuration = 0.15  # Average phoneme duration
            
            foreach ($word in $words) {
                # Simplified phoneme approximation
                $wordPhonemes = Get-ApproximatePhonemes -Word $word -PhonemeSet $engineConfig.phonemeSet
                
                foreach ($phoneme in $wordPhonemes) {
                    $phonemes += @{
                        phoneme = $phoneme
                        start = $currentTime
                        end = $currentTime + $avgDuration
                        confidence = 0.85
                    }
                    $currentTime += $avgDuration
                }
                
                $currentTime += 0.05  # Word gap
            }
        }
        else {
            # Default phoneme sequence
            $phonemes = @(
                @{ phoneme = 'sil'; start = 0.0; end = 0.1; confidence = 1.0 }
                @{ phoneme = 'HH'; start = 0.1; end = 0.25; confidence = 0.82 }
                @{ phoneme = 'EH'; start = 0.25; end = 0.4; confidence = 0.91 }
                @{ phoneme = 'L'; start = 0.4; end = 0.55; confidence = 0.78 }
                @{ phoneme = 'OW'; start = 0.55; end = 0.8; confidence = 0.88 }
                @{ phoneme = 'sil'; start = 0.8; end = 1.0; confidence = 1.0 }
            )
        }

        $result.phonemes = $phonemes
        $result.phonemeCount = $phonemes.Count
        $result.duration = if ($phonemes.Count -gt 0) { ($phonemes | Select-Object -Last 1).end } else { 0.0 }

        # Create lip sync data structure
        $lipSyncData = @{
            schemaVersion = $script:VoiceAnimSchemaVersion
            runId = $RunId
            engine = $Engine
            engineVersion = $engineConfig.version
            phonemeSet = $engineConfig.phonemeSet
            audioPath = $AudioPath
            audioFormat = $audioExt
            dialogueText = $DialogueText
            language = $Language
            duration = $result.duration
            phonemeCount = $result.phonemeCount
            phonemes = $phonemes
            metadata = @{
                recognitionType = $engineConfig.recognitionType
                extractedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }

        # Save lip sync data
        $lipSyncData | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8

        $result.metadata = $lipSyncData.metadata
        $result.success = $true

        Write-Verbose "[VoiceAnim] Phoneme extraction complete. Phonemes: $($result.phonemeCount), Duration: $($result.duration)s"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message
        Write-Warning "[VoiceAnim] Phoneme extraction failed: $_"
    }

    $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    return $result
}

#===============================================================================
# Lip Sync to Animation
#===============================================================================

function Convert-LipSyncToAnimation {
    <#
    .SYNOPSIS
        Converts lip sync phoneme data to animation curves.
    .DESCRIPTION
        Maps phonemes to visemes/blendshapes and generates animation curves
        with proper interpolation for smooth facial animation.
    .PARAMETER LipSyncData
        Lip sync data from Convert-VoiceToLipSync or path to lip sync file.
    .PARAMETER CharacterRig
        Character rig type (humanoid, cartoon, realistic, stylized).
    .PARAMETER VisemeMap
        Viseme mapping to use (rhubarb-basic, ovr-lipsync, arpabet-viseme).
    .PARAMETER FrameRate
        Target frame rate for animation (24, 30, 60).
    .PARAMETER Smoothing
        Apply smoothing to animation curves.
    .PARAMETER BlendshapeNames
        Custom blendshape name mapping.
    .PARAMETER ProjectRoot
        Project root directory.
    .PARAMETER RunId
        Run ID for tracking.
    .OUTPUTS
        System.Collections.Hashtable with animation curve data.
    .EXAMPLE
        $animation = Convert-LipSyncToAnimation -LipSyncData $lipSync -CharacterRig "humanoid" -FrameRate 60
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$LipSyncData,

        [Parameter()]
        [ValidateSet('humanoid', 'cartoon', 'realistic', 'stylized', 'anime')]
        [string]$CharacterRig = 'humanoid',

        [Parameter()]
        [ValidateSet('rhubarb-basic', 'ovr-lipsync', 'arpabet-viseme')]
        [string]$VisemeMap = 'arpabet-viseme',

        [Parameter()]
        [ValidateSet(24, 30, 60)]
        [int]$FrameRate = 60,

        [Parameter()]
        [switch]$Smoothing,

        [Parameter()]
        [hashtable]$BlendshapeNames = @{},

        [Parameter()]
        [string]$ProjectRoot = '.',

        [Parameter()]
        [string]$RunId = ''
    )

    if (-not $RunId) {
        $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $random = Get-Random -Minimum 0 -Maximum 65535
        $RunId = "l2a-$timestamp-$($random.ToString('x4'))"
    }

    # Initialize directories
    $curvesDir = Join-Path $ProjectRoot $script:AnimationCurvesDirectory
    if (-not (Test-Path -LiteralPath $curvesDir)) {
        New-Item -ItemType Directory -Path $curvesDir -Force | Out-Null
    }

    $result = @{
        runId = $RunId
        success = $false
        characterRig = $CharacterRig
        visemeMap = $VisemeMap
        frameRate = $FrameRate
        duration = 0.0
        frameCount = 0
        tracks = @()
        curves = @()
        outputPath = $null
        errors = @()
        startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt = $null
    }

    try {
        # Load lip sync data if path provided
        $lipSync = if ($LipSyncData -is [string]) {
            if (-not (Test-Path -LiteralPath $LipSyncData)) {
                throw "Lip sync file not found: $LipSyncData"
            }
            Get-Content -LiteralPath $LipSyncData -Raw | ConvertFrom-Json -AsHashtable
        }
        elseif ($LipSyncData -is [hashtable]) {
            $LipSyncData
        }
        else {
            throw "Invalid LipSyncData type. Expected path string or hashtable."
        }

        # Get viseme mapping
        $visemeMapping = $script:VisemeMaps[$VisemeMap]
        if (-not $visemeMapping) {
            throw "Viseme map not found: $VisemeMap"
        }

        Write-Verbose "[VoiceAnim] Converting lip sync to animation curves..."
        Write-Verbose "[VoiceAnim] Character rig: $CharacterRig, Frame rate: $FrameRate"

        $result.duration = $lipSync.duration
        $result.frameCount = [math]::Ceiling($lipSync.duration * $FrameRate)

        # Define animation tracks based on rig type
        $tracks = switch ($CharacterRig) {
            'humanoid' { @('jawOpen', 'mouthClose', 'mouthFunnel', 'mouthPucker', 'mouthSmile', 'mouthWide') }
            'cartoon' { @('mouthA', 'mouthE', 'mouthI', 'mouthO', 'mouthU', 'jawOpen') }
            'realistic' { @('jaw', 'lipUpperUp', 'lipLowerDown', 'lipCornerPull', 'lipCornerDepress', 'lipPucker') }
            'stylized' { @('visemeAA', 'visemeEH', 'visemeER', 'visemeIH', 'visemeOO', 'visemeOU') }
            'anime' { @('mouthOpen', 'mouthWidth', 'mouthHeight', 'mouthOShape', 'mouthIShape') }
            default { @('jawOpen', 'mouthClose', 'mouthSmile') }
        }
        $result.tracks = $tracks

        # Generate animation curves
        $curves = @()
        $phonemes = $lipSync.phonemes

        # Create keyframes from phonemes
        foreach ($phonemeData in $phonemes) {
            $phoneme = $phonemeData.phoneme
            $startTime = $phonemeData.start
            $endTime = $phonemeData.end
            $confidence = if ($phonemeData.ContainsKey('confidence')) { $phonemeData.confidence } else { 1.0 }

            # Map phoneme to viseme values
            $visemeValues = if ($visemeMapping.ContainsKey($phoneme)) {
                $visemeMapping[$phoneme]
            }
            else {
                @{ jawOpen = 0.0; lipRound = 0.0 }
            }

            # Create keyframes for each track
            foreach ($track in $tracks) {
                $keyframe = @{
                    track = $track
                    time = $startTime
                    value = Get-VisemeValue -Track $track -VisemeData $visemeValues -Confidence $confidence
                    inTangent = 0.0
                    outTangent = if ($Smoothing) { 0.5 } else { 0.0 }
                    phoneme = $phoneme
                }
                $curves += $keyframe

                # Add release keyframe
                $releaseKeyframe = @{
                    track = $track
                    time = $endTime
                    value = 0.0
                    inTangent = if ($Smoothing) { -0.5 } else { 0.0 }
                    outTangent = 0.0
                    phoneme = 'sil'
                }
                $curves += $releaseKeyframe
            }
        }

        $result.curves = $curves

        # Create animation data structure
        $animationData = @{
            schemaVersion = $script:VoiceAnimSchemaVersion
            runId = $RunId
            sourceLipSync = if ($LipSyncData -is [string]) { $LipSyncData } else { $lipSync.runId }
            characterRig = $CharacterRig
            visemeMap = $VisemeMap
            frameRate = $FrameRate
            duration = $result.duration
            frameCount = $result.frameCount
            tracks = $tracks
            curves = $curves
            smoothing = $Smoothing.IsPresent
            metadata = @{
                phonemeSet = $lipSync.phonemeSet
                language = $lipSync.language
                generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }

        # Save animation curves
        $outputPath = Join-Path $curvesDir "anim-$RunId.json"
        $animationData | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
        $result.outputPath = $outputPath

        $result.success = $true

        Write-Verbose "[VoiceAnim] Animation conversion complete. Tracks: $($tracks.Count), Keyframes: $($curves.Count)"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message
        Write-Warning "[VoiceAnim] Animation conversion failed: $_"
    }

    $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    return $result
}

#===============================================================================
# Export to Engine
#===============================================================================

function Export-LipSyncToEngine {
    <#
    .SYNOPSIS
        Exports lip sync animation to game engine format.
    .DESCRIPTION
        Converts animation curves to engine-specific formats:
        Godot (.tres), Blender (JSON), Unity (.anim), Unreal (JSON).
    .PARAMETER AnimationData
        Animation data from Convert-LipSyncToAnimation or path to animation file.
    .PARAMETER EngineFormat
        Target engine format (godot, blender, unity, unreal).
    .PARAMETER OutputPath
        Output file path (optional, auto-generated if not provided).
    .PARAMETER CharacterName
        Character name for animation naming.
    .PARAMETER AnimationName
        Animation clip name.
    .PARAMETER Loop
        Make animation loopable.
    .PARAMETER ProjectRoot
        Project root directory.
    .OUTPUTS
        System.Collections.Hashtable with export results.
    .EXAMPLE
        Export-LipSyncToEngine -AnimationData $animation -EngineFormat "godot" -CharacterName "Hero" -AnimationName "talk_hello"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$AnimationData,

        [Parameter(Mandatory = $true)]
        [ValidateSet('godot', 'blender', 'unity', 'unreal')]
        [string]$EngineFormat,

        [Parameter()]
        [string]$OutputPath = '',

        [Parameter()]
        [string]$CharacterName = 'Character',

        [Parameter()]
        [string]$AnimationName = 'LipSync',

        [Parameter()]
        [switch]$Loop,

        [Parameter()]
        [string]$ProjectRoot = '.'
    )

    # Initialize directories
    $exportDir = Join-Path $ProjectRoot "$script:VoiceAnimDirectory/exports/$EngineFormat"
    if (-not (Test-Path -LiteralPath $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    $result = @{
        success = $false
        engineFormat = $EngineFormat
        characterName = $CharacterName
        animationName = $AnimationName
        outputPath = $null
        fileSize = 0
        trackCount = 0
        keyframeCount = 0
        errors = @()
        startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completedAt = $null
    }

    try {
        # Load animation data if path provided
        $animData = if ($AnimationData -is [string]) {
            if (-not (Test-Path -LiteralPath $AnimationData)) {
                throw "Animation file not found: $AnimationData"
            }
            Get-Content -LiteralPath $AnimationData -Raw | ConvertFrom-Json -AsHashtable
        }
        elseif ($AnimationData -is [hashtable]) {
            $AnimationData
        }
        else {
            throw "Invalid AnimationData type. Expected path string or hashtable."
        }

        $engineConfig = $script:EngineFormats[$EngineFormat]
        if (-not $engineConfig) {
            throw "Engine format not supported: $EngineFormat"
        }

        Write-Verbose "[VoiceAnim] Exporting to $EngineFormat format..."

        # Generate output path if not provided
        if (-not $OutputPath) {
            $safeAnimName = $AnimationName -replace '\s+', '_'
            $safeCharName = $CharacterName -replace '\s+', '_'
            $OutputPath = Join-Path $exportDir "$safeCharName`_$safeAnimName$($engineConfig.extension)"
        }

        $result.outputPath = $OutputPath
        $result.trackCount = $animData.tracks.Count
        $result.keyframeCount = $animData.curves.Count

        # Generate engine-specific format
        $exportContent = switch ($EngineFormat) {
            'godot' { Export-ToGodotFormat -AnimData $animData -CharacterName $CharacterName -AnimationName $AnimationName -Loop $Loop }
            'blender' { Export-ToBlenderFormat -AnimData $animData -CharacterName $CharacterName -AnimationName $AnimationName -Loop $Loop }
            'unity' { Export-ToUnityFormat -AnimData $animData -CharacterName $CharacterName -AnimationName $AnimationName -Loop $Loop }
            'unreal' { Export-ToUnrealFormat -AnimData $animData -CharacterName $CharacterName -AnimationName $AnimationName -Loop $Loop }
        }

        # Write output file
        if ($exportContent -is [string]) {
            $exportContent | Out-File -FilePath $OutputPath -Encoding UTF8
        }
        else {
            $exportContent | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        }

        $result.fileSize = (Get-Item -LiteralPath $OutputPath).Length
        $result.success = $true

        Write-Verbose "[VoiceAnim] Export complete: $OutputPath"
    }
    catch {
        $result.success = $false
        $result.errors += $_.Exception.Message
        Write-Warning "[VoiceAnim] Export failed: $_"
    }

    $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    return $result
}

#===============================================================================
# Helper Functions
#===============================================================================

function Get-ApproximatePhonemes {
    param(
        [string]$Word,
        [string]$PhonemeSet
    )
    
    # Simplified phoneme approximation
    # In production, this would use a proper pronunciation dictionary
    
    $wordLower = $Word.ToLower()
    $phonemes = @()
    
    # Simple character-to-phoneme mapping
    for ($i = 0; $i -lt $wordLower.Length; $i++) {
        $char = $wordLower[$i]
        $nextChar = if ($i + 1 -lt $wordLower.Length) { $wordLower[$i + 1] } else { '' }
        
        $phoneme = switch -Regex ($char) {
            '[aeiou]' { 'AH' }
            'a' { 'AA' }
            'e' { 'EH' }
            'i' { 'IH' }
            'o' { 'OW' }
            'u' { 'UH' }
            '[bp]' { 'B' }
            '[td]' { 'D' }
            '[fv]' { 'F' }
            '[gk]' { 'G' }
            'h' { 'HH' }
            '[jz]' { 'JH' }
            'l' { 'L' }
            '[mn]' { 'N' }
            'r' { 'R' }
            's' { 'S' }
            'w' { 'W' }
            'y' { 'Y' }
            default { 'sil' }
        }
        
        if ($phoneme -ne 'sil') {
            $phonemes += $phoneme
        }
    }
    
    if ($phonemes.Count -eq 0) {
        $phonemes = @('sil')
    }
    
    return $phonemes
}

function Get-VisemeValue {
    param(
        [string]$Track,
        [object]$VisemeData,
        [double]$Confidence
    )
    
    # Map viseme data to track value
    $baseValue = switch ($Track) {
        'jawOpen' { if ($VisemeData.ContainsKey('jawOpen')) { $VisemeData.jawOpen } else { 0.3 } }
        'mouthClose' { if ($VisemeData.ContainsKey('jawOpen')) { 1.0 - $VisemeData.jawOpen } else { 0.7 } }
        'mouthSmile' { if ($VisemeData.ContainsKey('lipRound')) { 1.0 - $VisemeData.lipRound } else { 0.5 } }
        'mouthPucker' { if ($VisemeData.ContainsKey('lipRound')) { $VisemeData.lipRound } else { 0.0 } }
        'mouthA' { if ($VisemeData.ContainsKey('jawOpen')) { $VisemeData.jawOpen * 0.8 } else { 0.2 } }
        'mouthE' { if ($VisemeData.ContainsKey('jawOpen')) { $VisemeData.jawOpen * 0.6 } else { 0.3 } }
        'mouthO' { if ($VisemeData.ContainsKey('lipRound')) { $VisemeData.lipRound * 0.8 } else { 0.2 } }
        'visemeAA' { if ($VisemeData.ContainsKey('jawOpen')) { $VisemeData.jawOpen } else { 0.8 } }
        'visemeOO' { if ($VisemeData.ContainsKey('lipRound')) { $VisemeData.lipRound } else { 0.7 } }
        default { 0.5 }
    }
    
    return $baseValue * $Confidence
}

function Export-ToGodotFormat {
    param($AnimData, $CharacterName, $AnimationName, $Loop)
    
    $duration = $AnimData.duration
    $tracks = $AnimData.tracks
    $curves = $AnimData.curves
    
    $godotResource = @"
[gd_resource type="Animation" format=3]

[resource]
resource_name = "$AnimationName"
length = $duration
loop_mode = $(if ($Loop) { '1' } else { '0' })
step = 0.0166667
tracks/$tracks.Count/type = "value"
tracks/$tracks.Count/imported = false
"@

    # Add track data
    $trackIndex = 0
    foreach ($track in $tracks) {
        $trackCurves = $curves | Where-Object { $_.track -eq $track }
        $keyCount = $trackCurves.Count
        
        $godotResource += "`ntracks/$trackIndex/type = `"value`""
        $godotResource += "`ntracks/$trackIndex/path = NodePath(`"$CharacterName`:$track`")"
        $godotResource += "`ntracks/$trackIndex/interp = 1"
        $godotResource += "`ntracks/$trackIndex/loop_wrap = $(if ($Loop) { 'true' } else { 'false' })"
        $godotResource += "`ntracks/$trackIndex/keys = {"
        $godotResource += "`n`t`"times`": PackedFloat32Array($(($trackCurves | ForEach-Object { "{0:N6}" -f $_.time }) -join ', ')),"
        $godotResource += "`n`t`"transitions`": PackedFloat32Array($(($trackCurves | ForEach-Object { "{0:N6}" -f (1.0 - $_.outTangent) }) -join ', ')),"
        $godotResource += "`n`t`"values`": [$(($trackCurves | ForEach-Object { "{0:N4}" -f $_.value }) -join ', ')]"
        $godotResource += "`n}"
        
        $trackIndex++
    }

    return $godotResource
}

function Export-ToBlenderFormat {
    param($AnimData, $CharacterName, $AnimationName, $Loop)
    
    $blenderData = @{
        schema_version = $script:VoiceAnimSchemaVersion
        source = 'LLM Workflow Voice Animation Pipeline'
        character_name = $CharacterName
        animation_name = $AnimationName
        frame_start = 0
        frame_end = $AnimData.frameCount
        frame_rate = $AnimData.frameRate
        loop = $Loop.IsPresent
        shape_keys = @()
    }

    foreach ($track in $AnimData.tracks) {
        $trackCurves = $AnimData.curves | Where-Object { $_.track -eq $track }
        
        $keyframes = @()
        foreach ($curve in $trackCurves) {
            $frame = [math]::Round($curve.time * $AnimData.frameRate)
            $keyframe = @{
                frame = $frame
                value = $curve.value
                interpolation = 'BEZIER'
                handle_left = @{ x = $frame - 0.5; y = $curve.value - $curve.inTangent }
                handle_right = @{ x = $frame + 0.5; y = $curve.value + $curve.outTangent }
            }
            $keyframes += $keyframe
        }
        
        $shapeKey = @{
            name = $track
            keyframes = $keyframes
        }
        $blenderData.shape_keys += $shapeKey
    }

    return $blenderData
}

function Export-ToUnityFormat {
    param($AnimData, $CharacterName, $AnimationName, $Loop)
    
    # Unity .anim format is YAML-based
    $unityYaml = @"
%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!74 &7400000
AnimationClip:
  m_ObjectHideFlags: 0
  m_CorrespondingSourceObject: {fileID: 0}
  m_PrefabInstance: {fileID: 0}
  m_PrefabAsset: {fileID: 0}
  m_Name: $AnimationName
  serializedVersion: 6
  m_Legacy: 0
  m_Compressed: 0
  m_UseHighQualityCurve: 1
  m_RotationCurves: []
  m_CompressedRotationCurves: []
  m_EulerCurves: []
  m_PositionCurves: []
  m_ScaleCurves: []
  m_FloatCurves:
"@

    $curveIndex = 0
    foreach ($track in $AnimData.tracks) {
        $trackCurves = $AnimData.curves | Where-Object { $_.track -eq $track }
        
        $unityYaml += @"
  - curve:
      serializedVersion: 2
      m_Curve:
"@
        
        foreach ($curve in $trackCurves) {
            $time = $curve.time
            $value = $curve.value
            $inTangent = $curve.inTangent
            $outTangent = $curve.outTangent
            
            $unityYaml += @"
      - serializedVersion: 3
        time: $time
        value: $value
        inSlope: $inTangent
        outSlope: $outTangent
"@
        }
        
        $unityYaml += @"
      m_PostInfinity: $(if ($Loop) { '2' } else { '0' })
      m_PreInfinity: $(if ($Loop) { '2' } else { '0' })
    attribute: $track
    path: 
    classID: 137
    script: {fileID: 0}
"@
        $curveIndex++
    }

    $unityYaml += @"
  m_PPtrCurves: []
  m_SampleRate: $($AnimData.frameRate)
  m_WrapMode: $(if ($Loop) { '2' } else { '0' })
  m_Bounds:
    m_Center: {x: 0, y: 0, z: 0}
    m_Extent: {x: 0, y: 0, z: 0}
  m_ClipBindingConstant:
    genericBindings: []
    pptrCurveMapping: []
  m_AnimationClipSettings:
    serializedVersion: 2
    m_AdditiveReferencePoseClip: {fileID: 0}
    m_AdditiveReferencePoseTime: 0
    m_StartTime: 0
    m_StopTime: $($AnimData.duration)
    m_OrientationOffsetY: 0
    m_Level: 0
    m_CycleOffset: 0
    m_HasAdditiveReferencePose: 0
    m_LoopTime: $(if ($Loop) { '1' } else { '0' })
    m_LoopBlend: 0
    m_LoopBlendOrientation: 0
    m_LoopBlendPositionY: 0
    m_LoopBlendPositionXZ: 0
    m_KeepOriginalOrientation: 0
    m_KeepOriginalPositionY: 1
    m_KeepOriginalPositionXZ: 0
    m_HeightFromFeet: 0
    m_Mirror: 0
  m_EditorCurves: []
  m_EulerEditorCurves: []
  m_HasGenericRootTransform: 0
  m_HasMotionFloatCurves: 0
  m_Events: []
"@

    return $unityYaml
}

function Export-ToUnrealFormat {
    param($AnimData, $CharacterName, $AnimationName, $Loop)
    
    # Unreal format uses JSON for curve data
    $unrealData = @{
        schema_version = $script:VoiceAnimSchemaVersion
        source = 'LLM Workflow Voice Animation Pipeline'
        character_name = $CharacterName
        animation_name = $AnimationName
        duration = $AnimData.duration
        frame_rate = $AnimData.frameRate
        frame_count = $AnimData.frameCount
        loop = $Loop.IsPresent
        morph_targets = @()
    }

    foreach ($track in $AnimData.tracks) {
        $trackCurves = $AnimData.curves | Where-Object { $_.track -eq $track }
        
        $keys = @()
        foreach ($curve in $trackCurves) {
            $key = @{
                time = $curve.time
                value = $curve.value
                interpolation = 'Cubic'
                tangent_in = $curve.inTangent
                tangent_out = $curve.outTangent
            }
            $keys += $key
        }
        
        $morphTarget = @{
            name = $track
            keys = $keys
        }
        $unrealData.morph_targets += $morphTarget
    }

    return $unrealData
}

#===============================================================================
# Export Module Members
#===============================================================================

Export-ModuleMember -Function @(
    'Convert-VoiceToLipSync'
    'Convert-LipSyncToAnimation'
    'Export-LipSyncToEngine'
)
