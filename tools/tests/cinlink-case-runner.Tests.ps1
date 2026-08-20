$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$casePath = Join-Path $workspace 'test-cases\cinlink-ai-core.json'
$runnerPath = Join-Path $workspace 'tools\run-cinlink-cases.ps1'
$submitPath = Join-Path $workspace 'tools\cinlink-submit-task.ps1'

if (-not (Test-Path -LiteralPath $casePath -PathType Leaf)) {
    throw "Expected reusable case catalog: $casePath"
}
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Expected case runner: $runnerPath"
}

$catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $casePath | ConvertFrom-Json
$cases = @($catalog.cases)
if ($catalog.schemaVersion -ne 1) { throw 'Unexpected case schema version.' }
if ($cases.Count -ne 7) { throw 'The core catalog must contain seven workflow cases.' }
if (@($cases.id | Select-Object -Unique).Count -ne 7) { throw 'Case IDs must be unique.' }

foreach ($case in $cases) {
    if ([string]::IsNullOrWhiteSpace($case.id)) { throw 'A case is missing its ID.' }
    if ([string]::IsNullOrWhiteSpace($case.name)) { throw "Case $($case.id) is missing its name." }
    if ([string]::IsNullOrWhiteSpace($case.prompt)) { throw "Case $($case.id) is missing its prompt." }
    if (@($case.files).Count -lt 1) { throw "Case $($case.id) has no input files." }
    if (@($case.expected).Count -lt 1) { throw "Case $($case.id) has no expected results." }
}

$singleJson = & $runnerPath -CaseId 'CL-AI-001' -DryRun
$single = $singleJson | ConvertFrom-Json
if (@($single.cases).Count -ne 1 -or $single.cases[0].id -ne 'CL-AI-001') {
    throw 'Single-case dry-run selected the wrong case.'
}
if ($single.runDirectory -match '2026-08-20') {
    throw 'The runner must not reuse the old hard-coded evidence directory.'
}
if (-not $single.runDirectory.StartsWith((Join-Path $workspace 'output\ui-test\ai-core-smoke-'))) {
    throw 'The runner produced an unexpected run directory.'
}

$allJson = & $runnerPath -All -DryRun
$all = $allJson | ConvertFrom-Json
if (@($all.cases).Count -ne 7) { throw 'All-case dry-run must select seven cases.' }
if (-not $all.manualGateBetweenCases) { throw 'All-case execution must require a manual serial gate.' }

$submitRaw = Get-Content -Raw -LiteralPath $submitPath
if ($submitRaw -notmatch 'EvidenceDirectory') {
    throw 'The submit tool must accept a caller-provided evidence directory.'
}

$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$legacy = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $runnerPath -CaseId 'CL-AI-001' -DryRun
$legacyPlan = $legacy | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or @($legacyPlan.cases).Count -ne 1) {
    throw 'Windows PowerShell 5.1 could not execute the case runner dry-run.'
}

Write-Output 'PASS: reusable CinLink case catalog and runner checks.'
