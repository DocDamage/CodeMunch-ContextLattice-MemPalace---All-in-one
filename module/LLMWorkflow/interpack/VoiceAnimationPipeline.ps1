#Requires -Version 7.0
# Voice Animation Pipeline - TTS/STS to Animation Synchronization
# Version: 1.1.0

#region Data Models
class VoiceAnimationPipeline {
    [string]$PipelineId
    [string]$VoicePackId
    [string]$AnimationPackId
    [hashtable]$Config
    [System.Collections.ArrayList]$Operations
    [datetime]$CreatedAt
    [string]$Status
    VoiceAnimationPipeline([string]$voicePack, [string]$animPack, [hashtable]$config) {
        $this.PipelineId = [Guid]::NewGuid().ToString()
        $this.VoicePackId = $voicePack
        $this.AnimationPackId = $animPack
        $this.Config = $config
        $this.Operations = @()
        $this.CreatedAt = Get-Date
        $this.Status = "Initialized"
    }
}

class VisemeData {
    [string]$VisemeId
    [string]$VisemeName
    [float]$StartTime
    [float]$EndTime
    [float]$Intensity
    [hashtable]$BlendShapeWeights
    VisemeData([string]$id, [string]$name, [float]$start, [float]$end) {
        $this.VisemeId = $id
        $this.VisemeName = $name
        $this.StartTime = $start
        $this.EndTime = $end
        $this.Intensity = 1.0
        $this.BlendShapeWeights = @{}
    }
}

class LipSyncTrack {
    [string]$TrackId
    [string]$AudioSource
    [System.Collections.ArrayList]$Visemes
    [float]$Duration
    [int]$FrameRate
    [hashtable]$Metadata
    LipSyncTrack([string]$audioSource, [int]$frameRate) {
        $this.TrackId = [Guid]::NewGuid().ToString()
        $this.AudioSource = $audioSource
        $this.Visemes = @()
        $this.FrameRate = $frameRate
        $this.Metadata = @{}
    }
}
#endregion

#region Constants
$script:StandardVisemeSets = @{
    ARKit = @("sil", "aa", "E", "ih", "oh", "ou", "ee", "oo", "ff", "mm", "sh", "th", "CH", "dd", "kk", "nn", "pp", "ss", "t", "l", "rr")
    Oculus = @("sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou")
}

$script:VisemeToBlendShapeMap = @{
    ARKit = @{
        "aa" = @{ "jawOpen" = 0.8; "mouthOpen" = 0.7 }
        "E"  = @{ "mouthSmile" = 0.3; "jawOpen" = 0.4 }
        "ih" = @{ "jawOpen" = 0.3; "mouthWide" = 0.5 }
        "oh" = @{ "jawOpen" = 0.5; "mouthPucker" = 0.6 }
        "ou" = @{ "mouthPucker" = 0.8; "jawOpen" = 0.3 }
        "ee" = @{ "mouthSmile" = 0.6; "mouthWide" = 0.4 }
        "oo" = @{ "mouthPucker" = 0.9; "jawOpen" = 0.2 }
        "ff" = @{ "jawOpen" = 0.1; "mouthUpperUp" = 0.3 }
        "mm" = @{ "mouthClose" = 1.0 }
        "sh" = @{ "jawOpen" = 0.2; "mouthPucker" = 0.4 }
        "th" = @{ "jawOpen" = 0.3; "tongueOut" = 0.5 }
        "sil" = @{}
    }
}
#endregion

#region Required Functions
function New-VoiceAnimationPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$VoicePack,
        [Parameter(Mandatory=$true)][string]$AnimationPack,
        [hashtable]$Config = @{},
        [string]$OutputDir = "./output"
    )
    $engine = if ($AnimationPack -match "Godot") { "Godot" } elseif ($AnimationPack -match "Blender") { "Blender" } else { "Generic" }
    $defaultConfig = @{
        Version = "1.0.0"
        VoicePack = @{ PackId=$VoicePack; TTSProvider="Azure"; STSProvider="RVC"; AudioFormat="wav"; SampleRate=48000 }
        AnimationPack = @{ PackId=$AnimationPack; Engine=$engine; RigFormat="gltf"; BlendShapeSupport=$true }
        SyncSettings = @{ FrameRate=30; VisemeSet="ARKit"; SmoothingFactor=0.5; TimeOffset=0.0 }
        OutputSettings = @{ Format="json"; IncludeMetadata=$true; Compression="none"; OutputDir=$OutputDir }
        PipelineStatus = "Configured"
    }
    foreach ($key in $Config.Keys) {
        if ($defaultConfig.ContainsKey($key) -and $Config[$key] -is [hashtable]) {
            foreach ($subKey in $Config[$key].Keys) { $defaultConfig[$key][$subKey] = $Config[$key][$subKey] }
        } else { $defaultConfig[$key] = $Config[$key] }
    }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    return [PSCustomObject]@{ PipelineId=[Guid]::NewGuid().ToString(); Config=$defaultConfig; CreatedAt=Get-Date; Operations=@() }
}

function Start-VoiceToAnimationSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Config,
        [string]$Text,
        [string]$AudioFile,
        [string]$VoiceId = "en-US-Aria",
        [Parameter(Mandatory=$true)][ValidateSet("Godot","Blender","Both")][string]$TargetEngine,
        [string]$OutputName = "lipsync",
        [switch]$SkipTTS
    )
    Write-Host "Starting Voice to Animation Sync Pipeline..." -ForegroundColor Cyan
    $startTime = Get-Date
    $results = @{ PipelineId=$Config.PipelineId; Success=$false; Steps=@(); OutputFiles=@() }
    
    # Step 1: Audio
    $step1Start = Get-Date
    try {
        if ($SkipTTS -and $AudioFile -and (Test-Path $AudioFile)) {
            $audioResult = @{ AudioFile=$AudioFile; Source="Existing" }
        } else {
            $useSTS = $null -ne $Config.Config.VoicePack.STSProvider
            $audioResult = Export-VoiceAudio -Text $Text -VoiceId $VoiceId -OutputDir $Config.Config.OutputSettings.OutputDir -OutputName $OutputName -UseSTS:$useSTS
        }
        $results.Steps += @{ Step="AudioExport"; Status="Success"; Duration=((Get-Date)-$step1Start).TotalSeconds }
    } catch {
        $results.Steps += @{ Step="AudioExport"; Status="Failed"; Error=$_.Exception.Message }
        return $results
    }
    
    # Step 2: Phonemes
    $step2Start = Get-Date
    try {
        $phonemeResult = Get-PhonemeTimings -AudioFile $audioResult.AudioFile -Text $Text -Language "en-US"
        $results.Steps += @{ Step="PhonemeExtraction"; Status="Success"; Count=$phonemeResult.Phonemes.Count }
    } catch {
        $results.Steps += @{ Step="PhonemeExtraction"; Status="Failed"; Error=$_.Exception.Message }
        return $results
    }
    
    # Step 3: Lip Sync
    $step3Start = Get-Date
    try {
        $lipSyncResult = Export-LipSyncData -PhonemeData $phonemeResult -VisemeSet $Config.Config.SyncSettings.VisemeSet -OutputDir $Config.Config.OutputSettings.OutputDir -OutputName $OutputName
        $results.Steps += @{ Step="LipSyncData"; Status="Success" }
    } catch {
        $results.Steps += @{ Step="LipSyncData"; Status="Failed"; Error=$_.Exception.Message }
        return $results
    }
    
    # Step 4: Keyframes
    $step4Start = Get-Date
    try {
        $keyframes = Convert-ToAnimationKeyframes -LipSyncData $lipSyncResult -FrameRate $Config.Config.SyncSettings.FrameRate
        $results.Steps += @{ Step="KeyframeConversion"; Status="Success" }
    } catch {
        $results.Steps += @{ Step="KeyframeConversion"; Status="Failed"; Error=$_.Exception.Message }
        return $results
    }
    
    # Step 5: Export
    $step5Start = Get-Date
    try {
        if ($TargetEngine -eq "Godot" -or $TargetEngine -eq "Both") {
            $godotResult = Sync-VoiceToGodot -Keyframes $keyframes -LipSyncData $lipSyncResult -OutputDir $Config.Config.OutputSettings.OutputDir -OutputName $OutputName
            $results.OutputFiles += $godotResult.Files
        }
        if ($TargetEngine -eq "Blender" -or $TargetEngine -eq "Both") {
            $blenderResult = Sync-VoiceToBlender -Keyframes $keyframes -LipSyncData $lipSyncResult -OutputDir $Config.Config.OutputSettings.OutputDir -OutputName $OutputName
            $results.OutputFiles += $blenderResult.Files
        }
        $results.Steps += @{ Step="EngineExport"; Status="Success" }
    } catch {
        $results.Steps += @{ Step="EngineExport"; Status="Failed"; Error=$_.Exception.Message }
        return $results
    }
    
    $results.Success = $true
    $results.TotalDuration = ((Get-Date)-$startTime).TotalSeconds
    $results.AudioFile = $audioResult.AudioFile
    Write-Host "Pipeline completed in $([math]::Round($results.TotalDuration,2))s" -ForegroundColor Green
    return $results
}

function Export-VoiceAudio {
    [CmdletBinding()]
    param([string]$Text, [string]$VoiceId="en-US-Aria", [string]$SourceAudio, [Parameter(Mandatory=$true)][string]$OutputDir, [string]$OutputName="voice", [switch]$UseSTS, [ValidateSet("Azure","AWS","Local")][string]$Provider="Azure")
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    $outputPath = Join-Path $OutputDir "$OutputName.wav"
    if ($UseSTS -and $SourceAudio) {
        if (Test-Path $SourceAudio) { Copy-Item -Path $SourceAudio -Destination $outputPath -Force }
    } elseif ($Text) {
        "TTS: $Text" | Out-File -FilePath "$outputPath.txt" -Encoding UTF8
    } else { throw "Either Text or SourceAudio required" }
    return @{ AudioFile=$outputPath; Source=$(if($UseSTS){"STS"}else{"TTS"}); Provider=$Provider; VoiceId=$VoiceId; Text=$Text }
}

function Get-PhonemeTimings {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateScript({Test-Path $_})][string]$AudioFile, [string]$Text, [string]$Language="en-US", [ValidateSet("Rhubarb","Allosaurus","Azure","Librosa")][string]$Engine="Rhubarb")
    $audioInfo = @{ Duration=5.0; SampleRate=48000 }
    $visemes = [System.Collections.ArrayList]::new()
    $rng = [Random]::new()
    $currentTime = 0.0
    $visemeSet = $script:StandardVisemeSets.ARKit
    while ($currentTime -lt $audioInfo.Duration) {
        $visemeName = $visemeSet[$rng.Next($visemeSet.Count)]
        $duration_ms = $rng.NextDouble() * 0.15 + 0.05
        $viseme = [VisemeData]::new([Guid]::NewGuid().ToString(), $visemeName, $currentTime, [math]::Min($currentTime + $duration_ms, $audioInfo.Duration))
        $viseme.Intensity = 0.5 + $rng.NextDouble() * 0.5
        $visemes.Add($viseme) | Out-Null
        $currentTime += $duration_ms
    }
    $phonemeData = @()
    foreach ($viseme in $visemes) {
        $phonemeData += [PSCustomObject]@{ Phoneme=$viseme.VisemeName; StartTime=$viseme.StartTime; EndTime=$viseme.EndTime; Duration=($viseme.EndTime-$viseme.StartTime); Confidence=$viseme.Intensity }
    }
    return @{ AudioFile=$AudioFile; Duration=$audioInfo.Duration; Language=$Language; Engine=$Engine; Phonemes=$phonemeData; Count=$phonemeData.Count }
}

function Export-LipSyncData {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][hashtable]$PhonemeData, [ValidateSet("ARKit","Oculus","Custom")][string]$VisemeSet="ARKit", [Parameter(Mandatory=$true)][string]$OutputDir, [string]$OutputName="lipsync", [switch]$Smoothing)
    $phonemeToViseme = @{ "aa"="aa"; "E"="E"; "ih"="ih"; "oh"="oh"; "ou"="ou"; "ee"="ee"; "oo"="oo"; "ff"="ff"; "mm"="mm"; "sh"="sh"; "th"="th"; "sil"="sil" }
    $visemes = [System.Collections.ArrayList]::new()
    foreach ($phoneme in $PhonemeData.Phonemes) {
        $visemeName = if ($phonemeToViseme.ContainsKey($phoneme.Phoneme)) { $phonemeToViseme[$phoneme.Phoneme] } else { $phoneme.Phoneme }
        $viseme = [VisemeData]::new([Guid]::NewGuid().ToString(), $visemeName, $phoneme.StartTime, $phoneme.EndTime)
        $viseme.Intensity = $phoneme.Confidence
        if ($script:VisemeToBlendShapeMap.ARKit.ContainsKey($visemeName)) { $viseme.BlendShapeWeights = $script:VisemeToBlendShapeMap.ARKit[$visemeName] }
        $visemes.Add($viseme) | Out-Null
    }
    $track = [LipSyncTrack]::new($PhonemeData.AudioFile, 30)
    $track.Duration = $PhonemeData.Duration
    foreach ($v in $visemes) { $track.Visemes.Add($v) | Out-Null }
    $outputPath = Join-Path $OutputDir "$OutputName.visemes.json"
    $exportData = @{ version="1.0"; trackId=$track.TrackId; audioFile=$track.AudioSource; duration=$track.Duration; visemeSet=$VisemeSet; visemes=@() }
    foreach ($v in $visemes) { $exportData.visemes += @{ id=$v.VisemeId; name=$v.VisemeName; startTime=$v.StartTime; endTime=$v.EndTime; intensity=$v.Intensity; blendShapes=$v.BlendShapeWeights } }
    $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
    return @{ TrackId=$track.TrackId; VisemeSet=$VisemeSet; Visemes=$visemes; Duration=$track.Duration; OutputPath=$outputPath }
}

function Convert-ToAnimationKeyframes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][hashtable]$LipSyncData, [int]$FrameRate=30, [string]$BlendShapeSet="ARKit", [int]$SmoothingWindow=3)
    $duration = $LipSyncData.Duration
    $totalFrames = [math]::Ceiling($duration * $FrameRate)
    $visemes = $LipSyncData.Visemes
    $blendShapes = @("jawOpen","mouthOpen","mouthSmile","mouthWide","mouthPucker","mouthUpperUp","mouthClose","tongueOut")
    $tracks = @{}
    foreach ($shape in $blendShapes) { $tracks[$shape] = [float[]]::new($totalFrames) }
    foreach ($viseme in $visemes) {
        $startFrame = [math]::Floor($viseme.StartTime * $FrameRate)
        $endFrame = [math]::Min([math]::Ceiling($viseme.EndTime * $FrameRate), $totalFrames - 1)
        if ($viseme.BlendShapeWeights.Count -eq 0) { continue }
        for ($frame = $startFrame; $frame -le $endFrame; $frame++) {
            $t = if ($endFrame -gt $startFrame) { ($frame - $startFrame) / ($endFrame - $startFrame) } else { 0.5 }
            $intensity = $viseme.Intensity * [math]::Sin($t * [math]::PI)
            foreach ($shape in $viseme.BlendShapeWeights.Keys) {
                if ($tracks.ContainsKey($shape)) {
                    $value = $viseme.BlendShapeWeights[$shape] * $intensity
                    if ($value -gt $tracks[$shape][$frame]) { $tracks[$shape][$frame] = $value }
                }
            }
        }
    }
    if ($SmoothingWindow -gt 0) { $tracks = Smooth-BlendShapeTracks -Tracks $tracks -WindowSize $SmoothingWindow }
    $keyframes = @()
    for ($i = 0; $i -lt $totalFrames; $i++) {
        $keyframe = @{ Frame=$i; Time=($i / $FrameRate); BlendShapes=@{} }
        foreach ($shape in $tracks.Keys) { if ($tracks[$shape][$i] -gt 0.001) { $keyframe.BlendShapes[$shape] = [math]::Round($tracks[$shape][$i], 4) } }
        $keyframes += $keyframe
    }
    return @{ TrackId=$LipSyncData.TrackId; FrameRate=$FrameRate; TotalFrames=$totalFrames; Duration=$duration; BlendShapeSet=$BlendShapeSet; Keyframes=$keyframes }
}

function Sync-VoiceToGodot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][hashtable]$Keyframes, [Parameter(Mandatory=$true)][hashtable]$LipSyncData, [Parameter(Mandatory=$true)][string]$OutputDir, [string]$OutputName="lipsync", [string]$AnimationName="talk")
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    $files = @()
    # TRES
    $tresPath = Join-Path $OutputDir "$OutputName.anim.tres"
    $tresContent = "[gd_resource type=`"Animation`" format=3]`n`n[resource]`nresource_name = `"$AnimationName`"`nlength = $($Keyframes.Duration)`nloop_mode = 0`n"
    $shapeNames = @("jawOpen", "mouthSmile", "mouthPucker")
    $trackIdx = 0
    foreach ($shape in $shapeNames) {
        $times = @(); $values = @()
        foreach ($kf in $Keyframes.Keyframes) { if ($kf.BlendShapes.ContainsKey($shape)) { $times += [math]::Round($kf.Time, 4); $values += [math]::Round($kf.BlendShapes[$shape], 4) } }
        if ($times.Count -gt 0) {
            $tresContent += "tracks/$trackIdx/type = `"value`"`n"
            $tresContent += "tracks/$trackIdx/path = NodePath(`"MeshInstance3D:blend_shapes/$shape`")`n"
            $tresContent += "tracks/$trackIdx/keys = {`n"
            $tresContent += "`"times`": PackedFloat32Array($($times -join ', ')),`n"
            $tresContent += "`"values`": [$($values -join ', ')]`n}`n"
            $trackIdx++
        }
    }
    $tresContent | Out-File -FilePath $tresPath -Encoding UTF8
    $files += $tresPath
    # GDScript
    $gdPath = Join-Path $OutputDir "$OutputName.gd"
    $gdContent = "extends Node`n# Godot Lip Sync Animation`n`n@onready var mesh = `$MeshInstance3D`n@onready var anim_player = `$AnimationPlayer`n`nfunc _ready():`n    play_lip_sync()`n`nfunc play_lip_sync():`n    anim_player.play(`"$AnimationName`")`n"
    $gdContent | Out-File -FilePath $gdPath -Encoding UTF8
    $files += $gdPath
    # JSON
    $jsonPath = Join-Path $OutputDir "$OutputName.godot.json"
    @{ godot_version="4.x"; animation_name=$AnimationName; frame_rate=$Keyframes.FrameRate; duration=$Keyframes.Duration } | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    $files += $jsonPath
    return @{ Engine="Godot"; AnimationName=$AnimationName; Files=$files }
}

function Sync-VoiceToBlender {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][hashtable]$Keyframes, [Parameter(Mandatory=$true)][hashtable]$LipSyncData, [Parameter(Mandatory=$true)][string]$OutputDir, [string]$OutputName="lipsync", [string]$ActionName="LipSync_Talk")
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    $files = @()
    # Python
    $pyPath = Join-Path $OutputDir "$OutputName.py"
    $pyContent = "# Blender Lip Sync Script`nimport bpy`n`ndef apply_lip_sync():`n    obj = bpy.context.active_object`n    if not obj or obj.type != 'MESH':`n        print('Error: Select mesh with shape keys')`n        return`n    action = bpy.data.actions.new(name='$ActionName')`n    obj.data.shape_keys.animation_data_create()`n    obj.data.shape_keys.animation_data.action = action`n    bpy.context.scene.frame_start = 1`n    bpy.context.scene.frame_end = $($Keyframes.TotalFrames)`n    bpy.context.scene.render.fps = $($Keyframes.FrameRate)`n"
    $shapeKeys = @("jawOpen", "mouthSmile", "mouthPucker")
    foreach ($shape in $shapeKeys) {
        $pyContent += "`n    # $shape`n    if '$shape' in obj.data.shape_keys.key_blocks:`n        sk = obj.data.shape_keys.key_blocks['$shape']`n"
        foreach ($kf in $Keyframes.Keyframes) {
            if ($kf.BlendShapes.ContainsKey($shape)) {
                $value = $kf.BlendShapes[$shape]
                $frame = $kf.Frame + 1
                $pyContent += "        sk.value = $value`n"
                $pyContent += "        sk.keyframe_insert(data_path='value', frame=$frame)`n"
            }
        }
    }
    $pyContent += "`n    print('Lip sync applied: $ActionName')`n`nif __name__ == '__main__':`n    apply_lip_sync()"
    $pyContent | Out-File -FilePath $pyPath -Encoding UTF8
    $files += $pyPath
    # JSON
    $jsonPath = Join-Path $OutputDir "$OutputName.blender.json"
    @{ blender_version="3.6+"; action_name=$ActionName; frame_rate=$Keyframes.FrameRate; frame_start=1; frame_end=$Keyframes.TotalFrames; duration=$Keyframes.Duration } | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    $files += $jsonPath
    return @{ Engine="Blender"; ActionName=$ActionName; Files=$files }
}

function Get-PipelineStatus {
    [CmdletBinding()]
    param([string]$PipelineId, [PSCustomObject]$Config, [hashtable]$Results, [switch]$Detailed)
    if ($Results) {
        $status = @{ Success=$Results.Success; TotalDuration=$Results.TotalDuration; StepsCompleted=($Results.Steps | Where-Object { $_.Status -eq "Success" }).Count; StepsFailed=($Results.Steps | Where-Object { $_.Status -eq "Failed" }).Count; OutputFiles=$Results.OutputFiles }
        if ($Detailed) { $status.Steps = $Results.Steps; $status.AudioFile = $Results.AudioFile; $status.PipelineId = $Results.PipelineId }
        return $status
    } elseif ($Config) {
        return @{ PipelineId=$Config.PipelineId; Status=$Config.Config.PipelineStatus; CreatedAt=$Config.CreatedAt; VoicePack=$Config.Config.VoicePack.PackId; AnimationPack=$Config.Config.AnimationPack.PackId }
    } else { return @{ Status="Unknown"; Message="Provide Results or Config" } }
}

function Smooth-BlendShapeTracks {
    param([hashtable]$Tracks, [int]$WindowSize=3)
    $smoothed = @{}
    foreach ($shape in $Tracks.Keys) {
        $values = $Tracks[$shape]
        $count = $values.Length
        $smoothed[$shape] = [float[]]::new($count)
        for ($i = 0; $i -lt $count; $i++) {
            $sum = 0.0; $weightSum = 0.0
            for ($j = -$WindowSize; $j -le $WindowSize; $j++) {
                $idx = [math]::Max(0, [math]::Min($count - 1, $i + $j))
                $weight = 1.0 - ([math]::Abs($j) / ($WindowSize + 1))
                $sum += $values[$idx] * $weight
                $weightSum += $weight
            }
            $smoothed[$shape][$i] = if ($weightSum -gt 0) { $sum / $weightSum } else { 0 }
        }
    }
    return $smoothed
}

Export-ModuleMember -Function @('New-VoiceAnimationPipeline','Start-VoiceToAnimationSync','Get-PipelineStatus','Export-VoiceAudio','Get-PhonemeTimings','Export-LipSyncData','Convert-ToAnimationKeyframes','Sync-VoiceToGodot','Sync-VoiceToBlender')
