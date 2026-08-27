$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\sync-yunxiao-defects.ps1'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cinlink-yunxiao-regression-' + [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $fixtureRoot 'defects.json'
$evidencePath = Join-Path $fixtureRoot 'evidence.png'

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force
    [System.IO.File]::WriteAllBytes($evidencePath, [byte[]](1, 2, 3))
    @{
        runId = 'regression-fixture'
        defects = @(
            @{
                key = 'REG-001'
                level = 'P1'
                subject = '[CinLink][AI冒烟][P1] 新根因'
                matchSubjects = @('[CinLink][AI冒烟][P1] 已有同根因')
                jobId = 'run_fixture'
                material = 'fixture.mp4'
                prompt = 'fixture prompt'
                steps = @('提交任务')
                actual = @('结果错误')
                expected = @('结果正确')
                impact = 'fixture impact'
                evidence = @('evidence.png')
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

    $dryRunJson = & $scriptPath -DryRun -ConfigPath $configPath -EvidenceDirectory $fixtureRoot
    $dryRun = $dryRunJson | ConvertFrom-Json

    if ($dryRun.runId -ne 'regression-fixture') {
        throw 'External regression run ID was not preserved.'
    }
    if (@($dryRun.defects).Count -ne 1) {
        throw 'External defect configuration was not loaded.'
    }
    if (@($dryRun.defects[0].matchSubjects) -notcontains '[CinLink][AI冒烟][P1] 已有同根因') {
        throw 'Root-cause alias was not exposed for duplicate matching.'
    }
    if ($dryRun.defects[0].syncMarker -ne '<!-- cinlink-sync:regression-fixture:REG-001 -->') {
        throw 'Stable idempotency marker was not generated.'
    }
    if ($dryRun.defects[0].evidence[0] -ne $evidencePath) {
        throw 'Evidence path was not resolved from the selected run directory.'
    }

    Write-Output 'PASS: Yunxiao regression configuration and idempotency checks.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
