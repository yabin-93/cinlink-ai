param(
    [switch]$All,

    [ValidateSet('subtitle', 'translation', 'enhance', 'text-watermark', 'image-watermark', 'mix', 'long-to-short')]
    [string]$Workflow,

    [string]$CaseId,
    [switch]$NoRestart,
    [switch]$DryRun,
    [ValidateSet('Hybrid')]
    [string]$ExecutionMode = 'Hybrid',
    [string]$RunnerPath = (Join-Path $PSScriptRoot 'run-cinlink-cases.ps1')
)

$ErrorActionPreference = 'Stop'

$selectorCount = 0
if ($All) { $selectorCount++ }
if (-not [string]::IsNullOrWhiteSpace($Workflow)) { $selectorCount++ }
if (-not [string]::IsNullOrWhiteSpace($CaseId)) { $selectorCount++ }
if ($selectorCount -ne 1) {
    throw 'Choose exactly one selector: -All, -Workflow, or -CaseId.'
}

$resolvedRunnerPath = [IO.Path]::GetFullPath($RunnerPath)
if (-not (Test-Path -LiteralPath $resolvedRunnerPath -PathType Leaf)) {
    throw "Test runner does not exist: $resolvedRunnerPath"
}

$selector = [ordered]@{
    all = [bool]$All
    workflow = $Workflow
    caseId = $CaseId
}
$runnerArguments = @{}
$runnerArguments.ExecutionMode = $ExecutionMode
if ($All) { $runnerArguments.All = $true }
if (-not [string]::IsNullOrWhiteSpace($Workflow)) { $runnerArguments.Workflow = $Workflow }
if (-not [string]::IsNullOrWhiteSpace($CaseId)) { $runnerArguments.CaseId = $CaseId }
if ($NoRestart) { $runnerArguments.NoRestart = $true }
if ($DryRun) { $runnerArguments.DryRun = $true }

$startedAt = Get-Date
$runnerOutput = @(& $resolvedRunnerPath @runnerArguments)
foreach ($line in $runnerOutput) {
    Write-Host ([string]$line)
}

$runDirectory = $null
if (-not $DryRun) {
    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $outputRoot = Join-Path $repositoryRoot 'output\ui-test'
    if (Test-Path -LiteralPath $outputRoot -PathType Container) {
        $candidate = Get-ChildItem -LiteralPath $outputRoot -Directory |
            Where-Object { $_.Name -like 'ai-core-smoke-*' -and $_.LastWriteTime -ge $startedAt.AddSeconds(-5) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) {
            $runDirectory = $candidate.FullName
        }
    }
}

[ordered]@{
    stage = 'test'
    executionMode = $ExecutionMode.ToLowerInvariant()
    selector = $selector
    dryRun = [bool]$DryRun
    runDirectory = $runDirectory
} | ConvertTo-Json -Depth 5
