[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $InputPath,

    [string] $OutputPath,

    [string] $ReportPath,

    [ValidateRange(0.0, 1.0)]
    [double] $Threshold = 0.04,

    [string] $Margin = "0.2sec",

    [string] $Smooth = "0.2sec,0.1sec",

    [string] $PresetName = "Short edit",

    [switch] $Quiet
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
    $isInside = $fullPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)
    if (-not $isInside) {
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
        throw "Input must contain a video stream: $Path"
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

$inputFile = ConvertTo-WorkspacePath -Path $InputPath
Assert-NoReparsePoints -Path $inputFile
if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}

foreach ($tool in @($autoEditor, $ffmpeg)) {
    Assert-NoReparsePoints -Path $tool
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required tool not found: $(Get-WorkspaceRelativePath -Path $tool)"
    }
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($inputFile)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = "outputs/$baseName-short.mp4"
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = "outputs/$baseName-short-report.md"
}

$outputFile = ConvertTo-WorkspacePath -Path $OutputPath
$reportFile = ConvertTo-WorkspacePath -Path $ReportPath
Assert-NoReparsePoints -Path $autoEditor
Assert-NoReparsePoints -Path $ffmpeg
Assert-NoReparsePoints -Path $outputFile
Assert-NoReparsePoints -Path $reportFile

if ($inputFile.Equals($outputFile, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Output path must be different from the input path."
}
if ($reportFile.Equals($inputFile, [StringComparison]::OrdinalIgnoreCase) -or
    $reportFile.Equals($outputFile, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Report path must be different from the media paths."
}

New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($outputFile)) | Out-Null
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($reportFile)) | Out-Null
$intermediateFile = Join-Path ([IO.Path]::GetDirectoryName($outputFile)) ".smartcut-$([Guid]::NewGuid().ToString('N')).mp4"
Assert-NoReparsePoints -Path $intermediateFile

if (-not $Quiet) {
    Write-Host "[1/4] Reading input metadata"
}
$inputInfo = Get-MediaInfo -Path $inputFile

$thresholdText = Format-Number -Value $Threshold -Pattern "0.####"
$editMethod = "audio:threshold=$thresholdText"
$renderArguments = @(
    $inputFile,
    "--output", $intermediateFile,
    "--edit", $editMethod,
    "--margin", $Margin,
    "--smooth", $Smooth,
    "--pix-fmt", "yuv420p",
    "--progress", "none",
    "--no-open",
    "--no-cache"
)

if (-not $Quiet) {
    Write-Host "[2/4] Removing silence"
}
try {
    $renderLog = Invoke-AutoEditorCapture -Arguments $renderArguments
    if ($renderLog) {
        Write-Verbose $renderLog
    }
    if (-not (Test-Path -LiteralPath $intermediateFile -PathType Leaf)) {
        throw "Auto-Editor completed without creating the expected intermediate file."
    }

    if (-not $Quiet) {
        Write-Host "[3/4] Rendering center-filled 9:16"
    }
    $verticalFilter = "scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1"
    $ffmpegLog = & $ffmpeg `
        -hide_banner -loglevel error -nostdin -y `
        -i $intermediateFile `
        -map "0:v:0" -map "0:a?" `
        -vf $verticalFilter `
        -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p `
        -c:a aac -b:a 128k -movflags +faststart `
        $outputFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($ffmpegLog | Select-Object -Last 40 | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }
    if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf)) {
        throw "FFmpeg completed without creating the expected 9:16 output."
    }
}
finally {
    if (Test-Path -LiteralPath $intermediateFile -PathType Leaf) {
        Remove-Item -Force -LiteralPath $intermediateFile
    }
}

if (-not $Quiet) {
    Write-Host "[4/4] Writing edit report"
}
$outputInfo = Get-MediaInfo -Path $outputFile
$engineVersion = Invoke-AutoEditorCapture -Arguments @("--version")

$inputDuration = [double] $inputInfo.container.duration
$outputDuration = [double] $outputInfo.container.duration
$removedDuration = [Math]::Max(0.0, $inputDuration - $outputDuration)
$removedPercent = if ($inputDuration -gt 0) {
    ($removedDuration / $inputDuration) * 100.0
}
else {
    0.0
}

$inputResolution = @($inputInfo.video)[0].resolution
$outputResolution = @($outputInfo.video)[0].resolution
$inputName = Get-WorkspaceRelativePath -Path $inputFile
$outputName = Get-WorkspaceRelativePath -Path $outputFile
$reportName = Get-WorkspaceRelativePath -Path $reportFile

$report = @"
# $PresetName report

- Input: ``$inputName`` - $(Format-Number $inputDuration "0.00")s, $($inputResolution[0])x$($inputResolution[1])
- Output: ``$outputName`` - $(Format-Number $outputDuration "0.00")s, $($outputResolution[0])x$($outputResolution[1]) (9:16)
- Removed: $(Format-Number $removedDuration "0.00")s of silence ($(Format-Number $removedPercent "0.0")%)
- Settings: audio threshold $thresholdText, margin $Margin, smooth $Smooth
- Engine: Auto-Editor $engineVersion
"@

$report | Set-Content -LiteralPath $reportFile -Encoding UTF8

if (-not $Quiet) {
    Write-Host "Done: $outputName"
    Write-Host "Report: $reportName"
}
