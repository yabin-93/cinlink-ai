param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'skills\cinlink-ai-qa'),
    [string]$DestinationPath = 'C:\Users\chen\.codex\skills\cinlink-ai-qa',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$resolvedSource = [IO.Path]::GetFullPath($SourcePath)
$resolvedDestination = [IO.Path]::GetFullPath($DestinationPath)
$skillPath = Join-Path $resolvedSource 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
    throw "Skill source is missing SKILL.md: $resolvedSource"
}

$action = 'create-junction'
if (Test-Path -LiteralPath $resolvedDestination) {
    $item = Get-Item -LiteralPath $resolvedDestination -Force
    $isReparsePoint = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    $target = @($item.Target)[0]
    if (-not $isReparsePoint -or [string]::IsNullOrWhiteSpace($target)) {
        throw "Skill destination exists and is not a junction: $resolvedDestination"
    }
    $resolvedTarget = [IO.Path]::GetFullPath($target)
    if ($resolvedTarget -ne $resolvedSource) {
        throw "Skill destination points to a different source: $resolvedTarget"
    }
    $action = 'unchanged'
}

if (-not $DryRun -and $action -eq 'create-junction') {
    $parent = Split-Path $resolvedDestination -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $null = New-Item -ItemType Junction -Path $resolvedDestination -Target $resolvedSource
}

[ordered]@{
    action = $action
    source = $resolvedSource
    destination = $resolvedDestination
    dryRun = [bool]$DryRun
} | ConvertTo-Json -Depth 3
