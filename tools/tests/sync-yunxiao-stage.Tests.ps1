$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\sync-yunxiao-stage.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-yunxiao-stage-' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    '{"runId":"fixture","defects":[]}' | Set-Content -LiteralPath (Join-Path $fixtureRoot 'yunxiao-defects.json') -Encoding UTF8
    $fakeSync = Join-Path $fixtureRoot 'sync.ps1'
    @'
param([switch]$DryRun, [string]$ConfigPath, [string]$EvidenceDirectory)
[pscustomobject]@{ dryRun = [bool]$DryRun; configPath = $ConfigPath; evidenceDirectory = $EvidenceDirectory } | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $fakeSync -Encoding UTF8

    $preview = & $scriptPath -RunDirectory $fixtureRoot -DryRun -SyncToolPath $fakeSync | ConvertFrom-Json
    if (-not $preview.dryRun -or $preview.configPath -ne (Join-Path $fixtureRoot 'yunxiao-defects.json')) {
        throw 'Preview did not use the reviewed run configuration.'
    }

    $blocked = $false
    try {
        & $scriptPath -RunDirectory $fixtureRoot -SyncToolPath $fakeSync | Out-Null
    }
    catch {
        $blocked = $_.Exception.Message -like '*ConfirmWrite*'
    }
    if (-not $blocked) {
        throw 'Real synchronization was not blocked without explicit confirmation.'
    }

    Write-Output 'PASS: Yunxiao stage preview and write authorization checks.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
