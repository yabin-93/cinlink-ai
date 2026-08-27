$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\run-cinlink-test-stage.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-test-stage-' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $fakeRunner = Join-Path $fixtureRoot 'runner.ps1'
    @'
param([switch]$All, [string]$Workflow, [string]$CaseId, [switch]$NoRestart, [switch]$DryRun)
[pscustomobject]@{ All = [bool]$All; Workflow = $Workflow; CaseId = $CaseId; DryRun = [bool]$DryRun } | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $fakeRunner -Encoding UTF8

    $result = & $scriptPath -CaseId 'CL-AI-010' -DryRun -RunnerPath $fakeRunner | ConvertFrom-Json
    if ($result.stage -ne 'test' -or $result.selector.caseId -ne 'CL-AI-010' -or -not $result.dryRun) {
        throw 'Single-case DryRun was not forwarded correctly.'
    }

    $failed = $false
    try {
        & $scriptPath -All -Workflow 'subtitle' -DryRun -RunnerPath $fakeRunner | Out-Null
    }
    catch {
        $failed = $_.Exception.Message -like '*Choose exactly one selector*'
    }
    if (-not $failed) {
        throw 'Conflicting selectors were not rejected.'
    }

    Write-Output 'PASS: CinLink test stage selection and DryRun behavior.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
