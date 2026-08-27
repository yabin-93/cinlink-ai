$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$submitPath = Join-Path $workspace 'tools\cinlink-submit-task.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('cinlink-submit-' + [guid]::NewGuid().ToString('N'))

try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    $inputPath = Join-Path $fixtureRoot 'expected-video.mp4'
    Set-Content -LiteralPath $inputPath -Value 'fixture' -Encoding UTF8
    $callLog = Join-Path $fixtureRoot 'calls.txt'
    $fakeUploader = Join-Path $fixtureRoot 'upload.ps1'
    @'
param([string]$Selector, [string]$FilePath, [string]$NodePath, [string]$CdpCommandPath)
Add-Content -LiteralPath $env:CINLINK_SUBMIT_CALL_LOG -Value "upload:$Selector|$FilePath"
'@ | Set-Content -LiteralPath $fakeUploader -Encoding UTF8
    $fakeNode = Join-Path $fixtureRoot 'fake-node.ps1'
    @'
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
Add-Content -LiteralPath $env:CINLINK_SUBMIT_CALL_LOG -Value ($Arguments -join '|')
if ($true) {
    $value = $true
    $base64Index = [Array]::IndexOf($Arguments, '--params-base64')
    if ($base64Index -ge 0) {
        $paramsJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$Arguments[$base64Index + 1]))
        $params = $paramsJson | ConvertFrom-Json
        if ([string]$params.expression -like '*data-context-file*map*split*') {
            $value = @('expected-video.mp4')
        }
        elseif ([string]$params.expression -like '*data-context-file*length*') {
            $value = 0
        }
        elseif ([string]$params.expression -like '*sendDisabled*') {
            $value = @{ text = 'prompt'; sendDisabled = $false; context = @('expected-video.mp4') }
        }
    }
    @{ result = @{ type = 'object'; value = $value } } | ConvertTo-Json -Depth 6 -Compress
}
'@ | Set-Content -LiteralPath $fakeNode -Encoding UTF8
    $fakeCapture = Join-Path $fixtureRoot 'capture.ps1'
    @'
param([string]$ProcessName, [string]$OutputPath)
Set-Content -LiteralPath $OutputPath -Value 'screenshot' -Encoding UTF8
'@ | Set-Content -LiteralPath $fakeCapture -Encoding UTF8

    $env:CINLINK_SUBMIT_CALL_LOG = $callLog
    & $submitPath -Prompt 'prompt' -Files @($inputPath) -EvidenceName 'upload-check' `
        -EvidenceDirectory $fixtureRoot -NodePath $fakeNode -CapturePath $fakeCapture `
        -ContextUploaderPath $fakeUploader | Out-Null

    $calls = @(Get-Content -LiteralPath $callLog)
    if (@($calls | Where-Object { $_ -eq "upload:.composer-context-thumb|$inputPath" }).Count -ne 1) {
        throw 'The submitter must upload the requested file through the native-context uploader exactly once.'
    }
    $expressions = @($calls | Where-Object { $_ -like '*--params-base64*' } | ForEach-Object {
        $parts = $_ -split '\|'
        $base64Index = [Array]::IndexOf($parts, '--params-base64')
        if ($base64Index -ge 0) {
            ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[$base64Index + 1])) | ConvertFrom-Json).expression
        }
    })
    if (@($expressions | Where-Object { $_ -match '新建无项目会话' -and $_ -match '中新建会话' }).Count -ne 1) {
        throw 'The submitter must support both legacy non-project and CinLink 1.7.2 project-session buttons.'
    }
    Write-Output 'PASS: CinLink submitter uses validated native-context upload.'
}
finally {
    Remove-Item Env:CINLINK_SUBMIT_CALL_LOG -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
