param(
    [Parameter(Mandatory = $true)]
    [string]$RunDirectory,

    [switch]$DryRun,
    [switch]$ConfirmWrite,
    [string]$SyncToolPath = (Join-Path $PSScriptRoot 'sync-yunxiao-defects.ps1')
)

$ErrorActionPreference = 'Stop'

$resolvedRunDirectory = [IO.Path]::GetFullPath($RunDirectory)
if (-not (Test-Path -LiteralPath $resolvedRunDirectory -PathType Container)) {
    throw "Run directory does not exist: $resolvedRunDirectory"
}

$configPath = Join-Path $resolvedRunDirectory 'yunxiao-defects.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Reviewed Yunxiao defect configuration does not exist: $configPath"
}

$resolvedSyncToolPath = [IO.Path]::GetFullPath($SyncToolPath)
if (-not (Test-Path -LiteralPath $resolvedSyncToolPath -PathType Leaf)) {
    throw "Yunxiao sync tool does not exist: $resolvedSyncToolPath"
}

if (-not $DryRun -and -not $ConfirmWrite) {
    throw 'Real Yunxiao synchronization requires -ConfirmWrite after reviewing a DryRun preview.'
}

$syncArguments = @{
    ConfigPath = $configPath
    EvidenceDirectory = $resolvedRunDirectory
}
if ($DryRun) {
    $syncArguments.DryRun = $true
}

$syncOutput = @(& $resolvedSyncToolPath @syncArguments)
if ($DryRun) {
    $syncOutput
    return
}

foreach ($line in $syncOutput) {
    Write-Host ([string]$line)
}

$resultPath = Join-Path $resolvedRunDirectory 'yunxiao-defects-batch-result.json'
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "Yunxiao sync result does not exist: $resultPath"
}
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ([int]$result.verified -ne [int]$result.requested) {
    throw "Yunxiao sync readback was incomplete: $($result.verified)/$($result.requested)"
}

[ordered]@{
    stage = 'yunxiao'
    runDirectory = $resolvedRunDirectory
    requested = [int]$result.requested
    verified = [int]$result.verified
    created = [int]$result.created
    updatedExisting = [int]$result.updatedExisting
    skippedExisting = [int]$result.skippedExisting
    resultPath = $resultPath
} | ConvertTo-Json -Depth 5
