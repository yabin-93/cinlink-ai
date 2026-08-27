$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runnerPath = Join-Path $workspace 'tools\run-cinlink-cases.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-hybrid-' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $inputPath = Join-Path $fixtureRoot 'input.mp4'
    Set-Content -LiteralPath $inputPath -Value 'fixture' -Encoding UTF8
    $catalogPath = Join-Path $fixtureRoot 'catalog.json'
    @{
        schemaVersion = 1
        suite = 'hybrid-fixture'
        cases = @(
            @{
                id = 'CL-AI-901'; name = 'first'; workflow = 'subtitle'; variant = 'normal'; enabled = $true
                evidenceName = 'first'; prompt = 'first prompt'; files = @($inputPath); timeoutMinutes = 1
                manualActions = @(); expected = @('first expected')
            },
            @{
                id = 'CL-AI-902'; name = 'second'; workflow = 'enhance'; variant = 'normal'; enabled = $true
                evidenceName = 'second'; prompt = 'second prompt'; files = @($inputPath); timeoutMinutes = 1
                manualActions = @('confirm desktop action'); expected = @('second expected')
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $catalogPath -Encoding UTF8

    $eventPath = Join-Path $fixtureRoot 'events.txt'
    $submitterPath = Join-Path $fixtureRoot 'submit.ps1'
    @'
param([string]$Prompt, [string[]]$Files, [string]$EvidenceName, [string]$EvidenceDirectory)
Add-Content -LiteralPath $env:CINLINK_HYBRID_EVENT_PATH -Value "submit:$EvidenceName"
'@ | Set-Content -LiteralPath $submitterPath -Encoding UTF8

    $waiterPath = Join-Path $fixtureRoot 'wait.ps1'
    @'
param([string]$Prompt, [int]$TimeoutMinutes, [string]$EvidenceName, [string]$EvidenceDirectory)
Add-Content -LiteralPath $env:CINLINK_HYBRID_EVENT_PATH -Value "wait:$EvidenceName"
[pscustomobject]@{ status = 'completed'; jobId = "run_$EvidenceName"; artifacts = @() }
'@ | Set-Content -LiteralPath $waiterPath -Encoding UTF8

    $desktopPath = Join-Path $fixtureRoot 'desktop.ps1'
    @'
param([string]$CaseId, [string[]]$ManualActions, [string]$EvidenceDirectory, [string]$EvidenceName)
Add-Content -LiteralPath $env:CINLINK_HYBRID_EVENT_PATH -Value "desktop:$EvidenceName"
[pscustomobject]@{ status = 'completed' }
'@ | Set-Content -LiteralPath $desktopPath -Encoding UTF8

    $mediaPath = Join-Path $fixtureRoot 'media.ps1'
    @'
param([object[]]$Artifacts, [string]$EvidenceDirectory, [string]$EvidenceName)
Add-Content -LiteralPath $env:CINLINK_HYBRID_EVENT_PATH -Value "media:$EvidenceName"
[pscustomobject]@{ status = 'no-local-artifact' }
'@ | Set-Content -LiteralPath $mediaPath -Encoding UTF8

    $env:CINLINK_HYBRID_EVENT_PATH = $eventPath
    $runId = 'hybrid-fixture-' + [guid]::NewGuid().ToString('N')
    $result = & $runnerPath -All -CatalogPath $catalogPath -RunId $runId -NoRestart `
        -SubmitterPath $submitterPath -TerminalWaiterPath $waiterPath `
        -DesktopActionPath $desktopPath -MediaValidatorPath $mediaPath | Select-Object -Last 1 | ConvertFrom-Json

    $events = @(Get-Content -LiteralPath $eventPath)
    $expectedEvents = @('submit:first', 'wait:first', 'media:first', 'submit:second', 'desktop:second', 'wait:second', 'media:second')
    if (($events -join ',') -ne ($expectedEvents -join ',')) {
        throw "Hybrid execution was not serial. Actual: $($events -join ',')"
    }
    if ($result.executionMode -ne 'hybrid') { throw 'Hybrid must be the default execution mode.' }
    if ($result.executionStrategy.terminalGate -ne 'cdp') { throw 'CDP must be the terminal-state gate.' }
    if ($result.executionStrategy.desktopActions -ne 'open-computer-use') { throw 'Desktop actions must use Open Computer Use.' }
    if ($result.executionStrategy.mediaValidation -ne 'ffprobe') { throw 'Media validation must use ffprobe.' }
    if ($result.executionStrategy.browserAutomation -ne 'disabled') { throw 'Browser automation must be disabled.' }
    if (@($result.cases | Where-Object { $_.status -ne 'completed' }).Count -ne 0) {
        throw 'Fixture cases did not reach completed terminal states.'
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $result.runDirectory 'run-manifest.json') | ConvertFrom-Json
    if ($manifest.executionMode -ne 'hybrid' -or $manifest.executionStrategy.browserAutomation -ne 'disabled') {
        throw 'The persisted run manifest must record the hybrid strategy and disabled browser automation.'
    }

    Write-Output 'PASS: hybrid execution is the serial default.'
}
finally {
    Remove-Item Env:CINLINK_HYBRID_EVENT_PATH -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
    Get-ChildItem (Join-Path $workspace 'output\ui-test') -Directory -Filter 'hybrid-fixture-*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force
}
