[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $InputPath,

    [string] $OutputDirectory
)

$ErrorActionPreference = "Stop"

trap {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$workspacePrefix = $workspaceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$autoEditor = Join-Path $workspaceRoot "tools\auto-editor.exe"
$ffmpeg = Join-Path $workspaceRoot "tools\ffmpeg.exe"
$shortsScript = Join-Path $PSScriptRoot "shorts.ps1"

function ConvertTo-WorkspacePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $workspaceRoot $Path
    }

    $fullPath = [IO.Path]::GetFullPath($candidate)
    if (-not $fullPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must stay inside the repository: $Path"
    }

    return $fullPath
}

function Assert-NoReparsePoints {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $relativePath = $Path.Substring($workspacePrefix.Length)
    $currentPath = $workspaceRoot
    foreach ($segment in $relativePath.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $currentPath = Join-Path $currentPath $segment
        if (-not (Test-Path -LiteralPath $currentPath)) {
            break
        }

        $item = Get-Item -Force -LiteralPath $currentPath
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Symbolic links and junctions are not allowed in pipeline paths: $Path"
        }
    }
}

function Get-WorkspaceRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return $Path.Substring($workspacePrefix.Length).Replace("\", "/")
}

function Invoke-AutoEditorCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $captured = & $autoEditor @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($captured | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }

    return (($captured | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
}

function Get-MediaInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $json = Invoke-AutoEditorCapture -Arguments @("info", $Path, "--json")
    $document = $json | ConvertFrom-Json
    $entry = @($document.PSObject.Properties)[0].Value
    if ($null -eq $entry -or @($entry.video).Count -eq 0) {
        throw "Media must contain a video stream: $Path"
    }

    return $entry
}

function Format-Number {
    param(
        [Parameter(Mandatory = $true)]
        [double] $Value,

        [Parameter(Mandatory = $true)]
        [string] $Pattern
    )

    return $Value.ToString($Pattern, [Globalization.CultureInfo]::InvariantCulture)
}

function Get-TimelineMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InputFile,

        [Parameter(Mandatory = $true)]
        [double] $InputDuration,

        [Parameter(Mandatory = $true)]
        [double] $Threshold,

        [Parameter(Mandatory = $true)]
        [string] $Margin,

        [Parameter(Mandatory = $true)]
        [string] $Smooth,

        [Parameter(Mandatory = $true)]
        [string] $TemporaryTimeline
    )

    $thresholdText = Format-Number -Value $Threshold -Pattern "0.####"
    try {
        Invoke-AutoEditorCapture -Arguments @(
            $InputFile,
            "--edit", "audio:threshold=$thresholdText",
            "--margin", $Margin,
            "--smooth", $Smooth,
            "--export", "v3",
            "--output", $TemporaryTimeline,
            "--progress", "none",
            "--no-open",
            "--no-cache"
        ) | Out-Null

        $timeline = Get-Content -Raw -LiteralPath $TemporaryTimeline | ConvertFrom-Json
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryTimeline -PathType Leaf) {
            Remove-Item -Force -LiteralPath $TemporaryTimeline
        }
    }

    if ($timeline.timebase -notmatch '^(?<num>\d+)/(?<den>\d+)$') {
        throw "Unexpected timeline timebase: $($timeline.timebase)"
    }
    $ticksPerSecond = [double] $Matches.num / [double] $Matches.den
    $segments = if (@($timeline.a).Count -gt 0) {
        @($timeline.a[0])
    }
    elseif (@($timeline.v).Count -gt 0) {
        @($timeline.v[0])
    }
    else {
        @()
    }
    if ($segments.Count -eq 0) {
        throw "Auto-Editor produced no retained timeline segments."
    }

    $segmentLengths = @($segments | ForEach-Object { [double] $_.dur / $ticksPerSecond })
    $averageSegmentLength = ($segmentLengths | Measure-Object -Average).Average
    $veryShortSegmentCount = @($segmentLengths | Where-Object { $_ -lt 1.0 }).Count

    $cutCount = 0
    $previousSourceEnd = $null
    foreach ($segment in $segments) {
        $sourceStart = [long] $segment.offset
        if ($null -eq $previousSourceEnd) {
            if ($sourceStart -gt 0) {
                $cutCount++
            }
        }
        elseif ($sourceStart -gt $previousSourceEnd) {
            $cutCount++
        }
        $previousSourceEnd = $sourceStart + [long] $segment.dur
    }

    $inputTicks = [long] [Math]::Round($InputDuration * $ticksPerSecond)
    if ($null -ne $previousSourceEnd -and $inputTicks -gt $previousSourceEnd) {
        $cutCount++
    }
    $cutsPerMinute = if ($InputDuration -gt 0) {
        $cutCount / ($InputDuration / 60.0)
    }
    else {
        0.0
    }

    return [ordered]@{
        cutCount = $cutCount
        cutsPerMinute = [Math]::Round($cutsPerMinute, 2)
        retainedSegmentCount = $segments.Count
        averageRetainedSegmentSeconds = [Math]::Round([double] $averageSegmentLength, 3)
        veryShortSegmentCount = $veryShortSegmentCount
    }
}

function Get-RetainedSpeechDuration {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [double] $Duration
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $analysisLog = & $ffmpeg `
            -hide_banner -nostdin -i $Path `
            -vn -af "silencedetect=noise=-30dB:d=0.05" `
            -f null - 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw (($analysisLog | Select-Object -Last 40 | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }

    $silenceDuration = 0.0
    foreach ($line in $analysisLog) {
        if ($line.ToString() -match 'silence_duration:\s*(?<duration>\d+(?:\.\d+)?)') {
            $silenceDuration += [double]::Parse($Matches.duration, [Globalization.CultureInfo]::InvariantCulture)
        }
    }

    return [Math]::Round([Math]::Max(0.0, $Duration - $silenceDuration), 3)
}

function Get-HigherRangeScore {
    param([double] $Value, [double] $Minimum, [double] $Maximum)

    if (($Maximum - $Minimum) -lt 0.000001) {
        return 100.0
    }
    return 100.0 * (($Value - $Minimum) / ($Maximum - $Minimum))
}

function Get-LowerRangeScore {
    param([double] $Value, [double] $Minimum, [double] $Maximum)

    if (($Maximum - $Minimum) -lt 0.000001) {
        return 100.0
    }
    return 100.0 * (($Maximum - $Value) / ($Maximum - $Minimum))
}

$inputFile = ConvertTo-WorkspacePath -Path $InputPath
Assert-NoReparsePoints -Path $inputFile
if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}

foreach ($tool in @($autoEditor, $ffmpeg, $shortsScript)) {
    Assert-NoReparsePoints -Path $tool
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required tool not found: $(Get-WorkspaceRelativePath -Path $tool)"
    }
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($inputFile)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = "outputs/$baseName-smartcut-compare"
}

$outputRoot = ConvertTo-WorkspacePath -Path $OutputDirectory
Assert-NoReparsePoints -Path $outputRoot
if (Test-Path -LiteralPath $outputRoot -PathType Leaf) {
    throw "Output directory points to a file: $OutputDirectory"
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$inputInfo = Get-MediaInfo -Path $inputFile
$inputDuration = [double] $inputInfo.container.duration
$inputResolution = @($inputInfo.video)[0].resolution
$engineVersion = Invoke-AutoEditorCapture -Arguments @("--version")

$presets = @(
    [ordered]@{
        name = "Conservative"
        slug = "conservative"
        threshold = 0.035
        margin = "0.3sec"
        smooth = "0.3sec,0.05sec"
        color = "#66bb6a"
    },
    [ordered]@{
        name = "Balanced"
        slug = "balanced"
        threshold = 0.04
        margin = "0.2sec"
        smooth = "0.2sec,0.1sec"
        color = "#42a5f5"
    },
    [ordered]@{
        name = "Aggressive"
        slug = "aggressive"
        threshold = 0.08
        margin = "0.08sec"
        smooth = "0.08sec,0.3sec"
        color = "#ef5350"
    }
)

$results = @()
$stage = 0
foreach ($preset in $presets) {
    $stage++
    Write-Host "[$stage/5] Rendering $($preset.name)"
    $outputFile = Join-Path $outputRoot "$baseName-$($preset.slug).mp4"
    $reportFile = Join-Path $outputRoot "$baseName-$($preset.slug)-report.md"

    & $shortsScript `
        -InputPath $inputFile `
        -OutputPath $outputFile `
        -ReportPath $reportFile `
        -Threshold $preset.threshold `
        -Margin $preset.margin `
        -Smooth $preset.smooth `
        -PresetName "SmartCut $($preset.name)" `
        -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "$($preset.name) render failed."
    }

    $mediaInfo = Get-MediaInfo -Path $outputFile
    $finalDuration = [double] $mediaInfo.container.duration
    $outputResolution = @($mediaInfo.video)[0].resolution
    $removedDuration = [Math]::Max(0.0, $inputDuration - $finalDuration)
    $removedPercent = if ($inputDuration -gt 0) {
        ($removedDuration / $inputDuration) * 100.0
    }
    else {
        0.0
    }
    $temporaryTimeline = Join-Path $outputRoot ".smartcut-$($preset.slug)-$([Guid]::NewGuid().ToString('N')).v3"
    Assert-NoReparsePoints -Path $temporaryTimeline
    $timelineMetrics = Get-TimelineMetrics `
        -InputFile $inputFile `
        -InputDuration $inputDuration `
        -Threshold $preset.threshold `
        -Margin $preset.margin `
        -Smooth $preset.smooth `
        -TemporaryTimeline $temporaryTimeline
    $retainedSpeechDuration = Get-RetainedSpeechDuration -Path $outputFile -Duration $finalDuration

    $results += [ordered]@{
        name = $preset.name
        color = $preset.color
        settings = [ordered]@{
            audioThreshold = $preset.threshold
            margin = $preset.margin
            smooth = $preset.smooth
        }
        metrics = [ordered]@{
            percentageDurationRemoved = [Math]::Round($removedPercent, 1)
            cutCount = $timelineMetrics.cutCount
            cutsPerMinute = $timelineMetrics.cutsPerMinute
            retainedSegmentCount = $timelineMetrics.retainedSegmentCount
            averageRetainedSegmentSeconds = $timelineMetrics.averageRetainedSegmentSeconds
            veryShortSegmentCount = $timelineMetrics.veryShortSegmentCount
            retainedSpeechSeconds = $retainedSpeechDuration
        }
        output = Get-WorkspaceRelativePath -Path $outputFile
        report = Get-WorkspaceRelativePath -Path $reportFile
        originalDurationSeconds = [Math]::Round($inputDuration, 3)
        finalDurationSeconds = [Math]::Round($finalDuration, 3)
        timeRemovedSeconds = [Math]::Round($removedDuration, 3)
        percentRemoved = [Math]::Round($removedPercent, 1)
        resolution = @([int] $outputResolution[0], [int] $outputResolution[1])
    }
}

$removedMeasure = $results.metrics.percentageDurationRemoved | Measure-Object -Minimum -Maximum
$cutRateMeasure = $results.metrics.cutsPerMinute | Measure-Object -Minimum -Maximum
$shortSegmentMeasure = $results.metrics.veryShortSegmentCount | Measure-Object -Minimum -Maximum
$maximumAverageSegment = ($results.metrics.averageRetainedSegmentSeconds | Measure-Object -Maximum).Maximum
$maximumRetainedSpeech = ($results.metrics.retainedSpeechSeconds | Measure-Object -Maximum).Maximum
$scoreWeights = [ordered]@{
    durationRemoval = 0.30
    cutDensity = 0.20
    averageSegmentLength = 0.15
    shortSegmentSafety = 0.15
    speechRetention = 0.20
}

foreach ($result in $results) {
    $components = [ordered]@{
        durationRemoval = [Math]::Round((Get-HigherRangeScore `
            -Value $result.metrics.percentageDurationRemoved `
            -Minimum $removedMeasure.Minimum `
            -Maximum $removedMeasure.Maximum), 1)
        cutDensity = [Math]::Round((Get-LowerRangeScore `
            -Value $result.metrics.cutsPerMinute `
            -Minimum $cutRateMeasure.Minimum `
            -Maximum $cutRateMeasure.Maximum), 1)
        averageSegmentLength = if ($maximumAverageSegment -gt 0) {
            [Math]::Round(100.0 * $result.metrics.averageRetainedSegmentSeconds / $maximumAverageSegment, 1)
        }
        else {
            0.0
        }
        shortSegmentSafety = [Math]::Round((Get-LowerRangeScore `
            -Value $result.metrics.veryShortSegmentCount `
            -Minimum $shortSegmentMeasure.Minimum `
            -Maximum $shortSegmentMeasure.Maximum), 1)
        speechRetention = if ($maximumRetainedSpeech -gt 0) {
            [Math]::Round(100.0 * $result.metrics.retainedSpeechSeconds / $maximumRetainedSpeech, 1)
        }
        else {
            0.0
        }
    }

    $score = 0.0
    foreach ($componentName in $scoreWeights.Keys) {
        $score += [double] $components[$componentName] * [double] $scoreWeights[$componentName]
    }
    $result["score"] = [Math]::Round($score, 1)
    $result["scoreComponents"] = $components
}

$tieBreakRank = @{ Balanced = 0; Conservative = 1; Aggressive = 2 }
$recommended = @($results | Sort-Object `
    @{ Expression = { [double] $_.score }; Descending = $true },
    @{ Expression = { [int] $tieBreakRank[$_.name] }; Descending = $false })[0]
$numericScores = [ordered]@{}
foreach ($result in $results) {
    $numericScores[$result.name] = $result.score
}
$recommendationExplanation = "$($recommended.name) offers the strongest trade-off: " +
    "$(Format-Number $recommended.metrics.percentageDurationRemoved '0.0')% removed, " +
    "$(Format-Number $recommended.metrics.cutsPerMinute '0.00') cuts/min, " +
    "$(Format-Number $recommended.metrics.averageRetainedSegmentSeconds '0.00')s average retained segments, " +
    "$($recommended.metrics.veryShortSegmentCount) very short segments, and " +
    "$(Format-Number $recommended.metrics.retainedSpeechSeconds '0.00')s of detected speech retained."
$recommendation = [ordered]@{
    recommendedPreset = $recommended.name
    scores = $numericScores
    explanation = $recommendationExplanation
    methodology = [ordered]@{
        weights = $scoreWeights
        veryShortSegmentThresholdSeconds = 1.0
        speechDetection = "FFmpeg silencedetect, -30 dB threshold, 0.05s minimum silence"
        normalization = "Removal rewards more time saved; cut density and very short segments reward fewer; average segment length and retained speech reward more. Scores are relative to this three-preset run."
        tieBreakOrder = @("Balanced", "Conservative", "Aggressive")
    }
}

Write-Host "[4/5] Building side-by-side preview"
$previewFile = Join-Path $outputRoot "$baseName-comparison-preview.mp4"
$maxDuration = ($results | ForEach-Object { [double] $_.finalDurationSeconds } | Measure-Object -Maximum).Maximum
$durationText = Format-Number -Value $maxDuration -Pattern "0.###"
$filter = "[0:v]setpts=PTS-STARTPTS,scale=360:640,setsar=1,drawbox=x=0:y=0:w=iw:h=12:color=0x66bb6a:t=fill,tpad=stop_mode=clone:stop_duration=60[c];" +
    "[1:v]setpts=PTS-STARTPTS,scale=360:640,setsar=1,drawbox=x=0:y=0:w=iw:h=12:color=0x42a5f5:t=fill,tpad=stop_mode=clone:stop_duration=60[b];" +
    "[2:v]setpts=PTS-STARTPTS,scale=360:640,setsar=1,drawbox=x=0:y=0:w=iw:h=12:color=0xef5350:t=fill,tpad=stop_mode=clone:stop_duration=60[a];" +
    "[c][b][a]hstack=inputs=3[outv]"

$ffmpegArguments = @(
    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
    "-i", (Join-Path $outputRoot "$baseName-conservative.mp4"),
    "-i", (Join-Path $outputRoot "$baseName-balanced.mp4"),
    "-i", (Join-Path $outputRoot "$baseName-aggressive.mp4"),
    "-filter_complex", $filter,
    "-map", "[outv]", "-map", "0:a?",
    "-t", $durationText,
    "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
    "-movflags", "+faststart", $previewFile
)

$ffmpegLog = & $ffmpeg @ffmpegArguments 2>&1
if ($LASTEXITCODE -ne 0) {
    throw (($ffmpegLog | Select-Object -Last 40 | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
}
if (-not (Test-Path -LiteralPath $previewFile -PathType Leaf)) {
    throw "FFmpeg completed without creating the comparison preview."
}

Write-Host "[5/5] Writing scores and JSON summary"
$previewInfo = Get-MediaInfo -Path $previewFile
$previewResolution = @($previewInfo.video)[0].resolution
$ffmpegVersionLine = (& $ffmpeg -hide_banner -version 2>&1 | Select-Object -First 1).ToString()
$ffmpegVersion = if ($ffmpegVersionLine -match '^ffmpeg version ([^\s]+)') { $Matches[1] } else { $ffmpegVersionLine }
$summaryFile = Join-Path $outputRoot "$baseName-smartcut-summary.json"
$summary = [ordered]@{
    schemaVersion = 1
    input = [ordered]@{
        path = Get-WorkspaceRelativePath -Path $inputFile
        durationSeconds = [Math]::Round($inputDuration, 3)
        resolution = @([int] $inputResolution[0], [int] $inputResolution[1])
    }
    layout = @("Conservative", "Balanced", "Aggressive")
    versions = $results
    recommendation = $recommendation
    preview = [ordered]@{
        path = Get-WorkspaceRelativePath -Path $previewFile
        durationSeconds = [Math]::Round([double] $previewInfo.container.duration, 3)
        resolution = @([int] $previewResolution[0], [int] $previewResolution[1])
        markerColors = [ordered]@{
            Conservative = "#66bb6a"
            Balanced = "#42a5f5"
            Aggressive = "#ef5350"
        }
    }
    tools = [ordered]@{
        autoEditor = $engineVersion
        ffmpeg = $ffmpegVersion
    }
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryFile -Encoding UTF8

Write-Host "Done: $(Get-WorkspaceRelativePath -Path $outputRoot)"
Write-Host "Preview: $(Get-WorkspaceRelativePath -Path $previewFile)"
Write-Host "Summary: $(Get-WorkspaceRelativePath -Path $summaryFile)"
Write-Host "Recommended: $($recommended.name) ($($recommended.score)/100)"
Write-Host $recommendationExplanation
